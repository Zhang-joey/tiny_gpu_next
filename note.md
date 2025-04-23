# if-else的类型
    if-else
    a = b ? c : d
    switch-case

# if-else的实现方式
    int a
    if (cond)
        a = A()
    else
        a = B()
## flatten + 谓词指令
    int a
    b = A()
    c = B()
    movc a cond b c # 谓词指令
    
    优点:
        不需要跳转指令和SIMT stack
        不需要warp divergence和reconvergence
    缺点:
        所有核都重复执行了两条指令
        寄存器使用量增加
    执行代价不大时使用flatten(6-10 cycle)

## branch
    int a
    if (cond)
        a = A()
    else
        a = B()
    生成跳转指令
    需要SIMT stack
    需要warp divergence和reconvergence
    根据cond生成mask,先执行A, 再执行B
如果分支代价大,使用branch,分支代价不大,使用flatten

# 选用方法
    指令调度:
        SIMT stack元素:next_pc(per wave), active mask
    通过指令同步
    branch:单次

    