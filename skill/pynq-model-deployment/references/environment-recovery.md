# 环境、容器与运行恢复规则

以下来自实际协作中的准备阶段失败；用于选择排查层，不提供所有系统通用的一键修复命令。

|触发条件/原始表现|先检查|修正原则|失效或停止条件|
|Windows提示df不是命令|当前提示符、操作系统及shell|Linux命令在WSL/Linux执行；Windows命令在对应终端执行|不能因为安装了WSL就假设当前已进入Linux|
|找不到/workspace；容器中依赖消失|是否在宿主机、WSL或容器，实际Python路径及挂载|先确认执行层，再进入容器；明确宿主目录到容器目录映射|容器路径不能直接在宿主套用|
|粘贴后出现续行>、命令混入代码|引号、括号、heredoc结束标记及Markdown链接|命令用纯文本代码块；分块执行并检查返回，目录检查失败用return/受控异常|不要把交互shell的exit作为常规路径检查，以免意外退出会话|
|sudo密码不明、输入不显示|实际Linux用户；是否首次配置|密码不回显是常见终端行为；密码恢复按发行版管理流程处理|不把Windows账号密码等同Linux密码；不收集密码|
|apt列表被其他进程锁定|锁持有者、是否仍在更新|等待有效任务结束；确认进程状态后按管理流程处理|不删除锁文件伪装修复，不盲杀系统更新|
|Ubuntu软件源连接停滞|源地址、DNS、代理、网络|备份原配置，使用适配发行版的可信源；先确认update成功|不能把某一发行版代号复制到另一版本|
|docker.sock permission denied|当前用户组、socket属组、当前会话|按实际安装方式加入所需组并刷新会话，或使用正确授权入口|不chmod 777；桌面版/原生daemon路线不能混淆|
|切desktop-linux后protocol not available|docker context endpoint与执行系统|Linux CLI使用该系统可用的endpoint；Windows命名管道不能当Linux Unix socket|不固定要求所有机器用名为default的context|
|docker-credential-desktop.exe找不到|实际DOCKER_CONFIG、credential helper和PATH|修正helper安装/PATH；匿名拉取可使用单独最小配置目录|不覆盖原登录配置、不删除全部credHelpers；私有镜像仍需有效认证|
|--config参数在Windows不正确|shell变量展开规则|PowerShell、CMD、Bash分别使用其路径语法；输出实际生效目录|不能在CMD里照抄Bash的$HOME|
|registry-1.docker.io超时|daemon实际代理、DNS解析、路由及日志|Docker拉取是daemon联网；按安装方式配置其可用代理和网络|WSL终端能联网不证明daemon能联网；不循环重装量化环境|
|代理为localhost但WSL/daemon无法使用|代理监听地址、NAT/镜像模式、daemon所在环境|采用实际可达且获授权的地址；记录代理作用于CLI还是daemon|不能普遍将localhost、宿主IP或某个端口硬编码|
|镜像站not in allowlist|镜像站支持范围、原镜像坐标|换可用且可信的获取路线，保留来源与digest|不把镜像站拒绝解释为官方镜像不存在|
|层下载EOF|是否瞬时中断、磁盘、代理/CDN连接|修复连接后重新pull，利用已有层；检查最终digest和完成状态|部分层完成不等于镜像完成，不无限重试|
|镜像名/版本不确定|官方对应release与本地镜像digest|使用真实存在且匹配工作流的镜像并锁定版本/digest|latest不可证明可复现；CPU/GPU镜像不能仅凭名称猜兼容|
|No CUDA runtime警告|任务是否明确使用CPU|CPU量化允许无CUDA；以实际异常和结果判断|没有CUDA不等于PTQ失败；不为消除提示盲装CUDA|
|/dev/dri不存在|脚本是否只是探测可选设备、是否进入容器|CPU路线若不需要该设备且后续正常，可标为非阻断警告|硬件加速路线若必需则不能忽略|
|容器退出后手装包丢失|是否--rm、是否新建容器、依赖安装位置|固定Dockerfile/依赖清单/镜像digest；持久挂载数据产物|保存数据不等于保存环境；docker commit只能辅助快照，不能替代构建说明|
|用户配置目录不可写|HOME、UID、挂载权限|为工具指定可写且可持久化的配置目录|不递归chown整个厂商环境来处理单一配置目录|
|脚本意外停止、日志不再刷新|进程是否存在、最后写入时间、退出码|确认停机后再恢复；日志停滞不能单独证明活跃或完成|不要重复启动同一输出目录的多个流水线|
|续训被变成重新训练或多训练轮数|checkpoint epoch、optimizer、train_args、激活结构|恢复优化器/调度状态，按总轮数结束；保留最佳验证权重|缺优化器的推理权重不等同可精确续训的断点|

历史效果范围：本次协作曾分别修复Docker组权限、context、credential helper、代理/网络、容器依赖和执行目录等问题后进入量化；本轮续训完成50轮。未对上述所有规则在新机器或其他系统重演，不能标记为全平台自动修复成功。
