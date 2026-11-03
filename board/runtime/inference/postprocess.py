"""Single-class YOLOv8 six-head decoding. Only NumPy is required offline."""
from dataclasses import dataclass
import numpy as np


@dataclass(frozen=True)
class ImageTransform:
    width: int = 640
    height: int = 480
    scale: float = 1.0
    pad_x: float = 0.0
    pad_y: float = 80.0

    def __post_init__(self):
        if (self.width <= 0 or self.height <= 0 or
                not np.isfinite([self.scale, self.pad_x, self.pad_y]).all() or self.scale <= 0):
            raise ValueError('Invalid source image transform')
        if (self.pad_x < 0 or self.pad_y < 0 or
                self.pad_x + self.width * self.scale > 640.001 or
                self.pad_y + self.height * self.scale > 640.001):
            raise ValueError('Transform must fit the 640x640 input')

    def restore(self, boxes):
        boxes = np.array(boxes, dtype=np.float32, copy=True)
        boxes[:, [0, 2]] = np.clip((boxes[:, [0, 2]] - self.pad_x) / self.scale, 0, self.width)
        boxes[:, [1, 3]] = np.clip((boxes[:, [1, 3]] - self.pad_y) / self.scale, 0, self.height)
        return boxes


def sigmoid(x):
    # Stable for both signs; no overflow even for extreme finite logits.
    z = np.exp(-np.abs(x))
    return np.where(x >= 0, 1.0 / (1.0 + z), z / (1.0 + z))


def nms(boxes, scores, iou_threshold=0.45, max_detections=100):
    """Greedy single-class NMS on continuous xyxy coordinates, no '+1'."""
    if not 0 <= iou_threshold <= 1 or max_detections <= 0:
        raise ValueError('Invalid NMS settings')
    boxes = np.asarray(boxes, dtype=np.float32)
    scores = np.asarray(scores, dtype=np.float32)
    if boxes.shape != (scores.size, 4) or scores.ndim != 1:
        raise ValueError('Expected boxes (N,4), scores (N,)')
    if not np.isfinite(boxes).all() or not np.isfinite(scores).all():
        raise ValueError('NMS requires finite values')
    order = np.argsort(-scores, kind='stable')
    area = np.maximum(boxes[:, 2] - boxes[:, 0], 0) * np.maximum(boxes[:, 3] - boxes[:, 1], 0)
    keep = []
    while order.size and len(keep) < max_detections:
        i = order[0]
        keep.append(int(i))
        rest = order[1:]
        wh = np.maximum(0, np.minimum(boxes[i, 2:], boxes[rest, 2:]) -
                        np.maximum(boxes[i, :2], boxes[rest, :2]))
        intersection = wh[:, 0] * wh[:, 1]
        union = area[i] + area[rest] - intersection
        iou = np.divide(intersection, union, out=np.zeros_like(intersection), where=union > 0)
        order = rest[iou <= iou_threshold]
    return np.asarray(keep, dtype=np.int64)


def decode(logits, transform=None, confidence=0.25, iou_threshold=0.45, max_detections=100):
    """cv2_i NHWC [1,H,W,64], cv3_i [1,H,W,1], i=0..2.

    Returns list of {bbox: [left,top,width,height], confidence: float,
    class_id: 0}, in source image pixel coordinates. No objectness branch.
    """
    if not 0 <= confidence <= 1 or not 0 <= iou_threshold <= 1 or max_detections <= 0:
        raise ValueError('Invalid decoder settings')
    transform = transform or ImageTransform()
    boxes_all, scores_all = [], []
    for level, (size, stride) in enumerate(((80, 8), (40, 16), (20, 32))):
        reg = np.asarray(logits['cv2_%d' % level], dtype=np.float32)
        cls = np.asarray(logits['cv3_%d' % level], dtype=np.float32)
        if reg.shape != (1, size, size, 64) or cls.shape != (1, size, size, 1):
            raise ValueError('Incorrect six-head NHWC shape at level %d' % level)
        if not np.isfinite(reg).all() or not np.isfinite(cls).all():
            raise ValueError('Non-finite logits')
        scores = sigmoid(cls.reshape(-1))
        indices = np.flatnonzero(scores >= confidence)
        if not indices.size:
            continue
        # Four contiguous l,t,r,b distributions, each with reg_max=16.
        dist = reg.reshape(-1, 4, 16)[indices]
        prob = np.exp(dist - dist.max(axis=-1, keepdims=True))
        prob /= prob.sum(axis=-1, keepdims=True)
        ltrb = (prob * np.arange(16, dtype=np.float32)).sum(axis=-1) * stride
        centers = np.column_stack((indices % size + 0.5, indices // size + 0.5)) * stride
        boxes_all.append(np.column_stack((centers - ltrb[:, :2], centers + ltrb[:, 2:])))
        scores_all.append(scores[indices])
    if not boxes_all:
        return []
    boxes = np.concatenate(boxes_all).astype(np.float32)
    scores = np.concatenate(scores_all)
    # NMS in model space, then undo exactly one source transform and clip.
    keep = nms(boxes, scores, iou_threshold, max_detections)
    restored = transform.restore(boxes[keep])
    result = []
    for b, score in zip(restored, scores[keep]):
        if b[2] <= b[0] or b[3] <= b[1]:
            continue
        result.append({'bbox': [float(b[0]), float(b[1]), float(b[2]-b[0]), float(b[3]-b[1])],
                       'confidence': float(score), 'class_id': 0})
    return result
