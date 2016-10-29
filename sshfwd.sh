#!/bin/bash

conf_file=sshfwd.conf
script_dir=$(cd `dirname $0`;pwd)

monitor_interval_secs=299

cmd_ssh="/usr/bin/ssh -o ConnectTimeout=15"
cmd_sshpass="/usr/bin/sshpass"

servers=()
proc_main=""
procs=()
spr="_#_"


# load conf from file and validate every line
line_nbr=1
while read line;
do
    line=`echo $line|sed 's/^ //;s/ $//'`
    ch1=${line:0:1}
    # lines starting with '#' are skipped
    if [ "#" != "$ch1" -a "" != "$ch1" ]; then
        segs=($(echo $line|tr $spr ' '))
        if [ ${#segs[@]} -lt 6 -o ${#segs[@]} -gt 9 ]; then
            echo invalid conf in line $line_nbr in $conf_file : number of elements per line should be 6 or 7!
            exit 1
        fi
        servers=("${servers[@]}" "$line")
    fi
    let "line_nbr+=1"
done < $script_dir/$conf_file


fn_get_procs() {
    proc_main=`ps -ef | grep sshfwd | grep start | grep -v "$$" | grep -v grep | awk '{printf "%s ",$2}'`
    procs=()
    for server in ${servers[@]}; do
        segs=($(echo $server|tr $spr ' '))
        tunnel_id=${segs[0]}
        listen_addr=${segs[1]}
        listen_port=${segs[2]}
        ssh_host=""
        ssh_port=""
        user=""
        if [ ${#segs[@]} -ge 6 -a ${#segs[@]} -le 7 ]; then
            ssh_host=${segs[3]}
            ssh_port=${segs[4]}
            user=${segs[5]}
        elif [ ${#segs[@]} -ge 8 -a ${#segs[@]} -le 9 ]; then
            ssh_host=${segs[5]}
            ssh_port=${segs[6]}
            user=${segs[7]}
        else
            echo "Error: wrong ssh server conf: ${segs[@]}"
        fi
        proc=$spr`ps -ef | grep ssh | grep ${segs[2]} | grep ${segs[3]} | grep ${segs[5]}| grep -v grep | awk '{printf "%s_#_",$2}'`
        procs=("${procs[@]}" "$proc")
    done
}

fn_get_procs


fn_start_tunnel_type_a() {
    tunnel_id=$1
    listen_addr=$2
    listen_port=$3
    ssh_host=$4
    ssh_port=$5
    user=$6
    pwd=$7
    if [ "" = "$pwd" ]; then
        sh -c "$cmd_ssh -N -C -f -D$listen_addr:$listen_port -o PreferredAuthentications=publickey -p $ssh_port $user@$ssh_host" > /dev/null 2>&1
    else
        sh -c "$cmd_sshpass -p$pwd $cmd_ssh -N -C -f -D$listen_addr:$listen_port -p $ssh_port -o PreferredAuthentications=password -o StrictHostKeyChecking=no $user@$ssh_host" > /dev/null 2>&1
    fi

    if [ $? = 0 ]; then
        echo "tunnel $tunnel_id (port = ${listen_port}) started"
    else
        echo "failed to start tunnel $tunnel_id"
    fi
}

fn_start_tunnel_type_b() {
    tunnel_id=$1
    listen_addr=$2
    listen_port=$3
    forwarded_addr=$4
    forwarded_port=$5
    ssh_host=$6
    ssh_port=$7
    user=$8
    pwd=$9
    if [ "" = "$pwd" ]; then
        sh -c "$cmd_ssh -N -C -f -L $listen_addr:$listen_port:$forwarded_addr:$forwarded_port -o PreferredAuthentications=publickey -p $ssh_port $user@$ssh_host" > /dev/null 2>&1
    else
        sh -c "$cmd_sshpass -p$pwd $cmd_ssh -N -C -f -L $listen_addr:$listen_port:$forwarded_addr:$forwarded_port -p $ssh_port -o PreferredAuthentications=password -o StrictHostKeyChecking=no $user@$ssh_host" > /dev/null 2>&1
    fi

    if [ $? = 0 ]; then
        echo "tunnel $tunnel_id (port = ${listen_port}) started"
    else
        echo "failed to start tunnel $tunnel_id"
    fi
}


fn_start() {
    i=0
    for server in ${servers[@]}; do
        segs=($(echo $server|tr $spr ' '))
        pids=($(echo ${procs[$i]}|tr $spr ' '))
        pids_squashed=($(echo $pids|tr -t $spr ''|tr -t ' ' ''))
        tunnel_id=${segs[0]}
        listen_addr=${segs[1]}
        listen_port=${segs[2]}
        if [ "" = "$pids_squashed" ]; then
            if [ ${#segs[@]} -ge 6 -a ${#segs[@]} -le 7 ]; then
                ssh_host=${segs[3]}
                ssh_port=${segs[4]}
                user=${segs[5]}
                pwd=${segs[6]}
                fn_start_tunnel_type_a $tunnel_id $listen_addr $listen_port $ssh_host $ssh_port $user $pwd
            elif [ ${#segs[@]} -ge 8 -a ${#segs[@]} -le 9 ]; then
                forwarded_addr=${segs[3]}
                forwarded_port=${segs[4]}
                ssh_host=${segs[5]}
                ssh_port=${segs[6]}
                user=${segs[7]}
                pwd=${segs[8]}
                fn_start_tunnel_type_b $tunnel_id $listen_addr $listen_port $forwarded_addr $forwarded_port $ssh_host $ssh_port $user $pwd
            else
                echo "Error: wrong ssh server conf: ${segs[@]}"
            fi
        else
            echo "tunnel $tunnel_id (port = ${listen_port}) is already running: pid = $pids"
        fi
        let "i+=1"
    done
}


fn_stop_all() {
    i=0
    for server in ${servers[@]}; do
        segs=($(echo $server|tr $spr ' '))
        pids=($(echo ${procs[$i]}|tr $spr ' '))
        pids_squashed=($(echo $pids|tr -t $spr ''|tr -t ' ' ''))
        tunnel_id=${segs[0]}
        if [ "" = "$pids_squashed" ]; then
            echo "tunnel $tunnel_id is not running"
        else
            sh -c "kill $pids"
            if [ $? = 0 ]; then
                echo "tunnel $tunnel_id stopped"
            else
                echo "failed stop tunnel $tunnel_id pid = $pids"
            fi
        fi
        let "i+=1"
    done

    if [ "" = "$proc_main" ]; then
        echo "sshfwd monitor is not running"
    else
        kill $proc_main
        if [ $? = 0 ]; then
            echo "sshfwd monitor stopped"
        else
            echo "failed to stop sshfwd monitor"
        fi
    fi
}

fn_restart() {
    fn_stop_all
    sleep 1
    fn_get_procs
    fn_start
    fn_run_monitor &
    # we must sleep 1 sec to make sure forked fn_run_monitor process can get its parent's process (the current process)
    sleep 1
}

fn_status() {
    pids_grep="dummydummy"
    i=0
    for server in ${servers[@]}; do
        segs=($(echo $server|tr $spr ' '))
        pids=($(echo ${procs[$i]}|tr $spr ' '))
        pids_squashed=($(echo $pids|tr -t ' ' ''))
        tunnel_id=${segs[0]}
        listen_port=${segs[2]}
        pids_grep=$pids_grep"|"$listen_port
        if [ "" = "$pids_squashed" ]; then
            echo "tunnel $tunnel_id is not running"
        else
            echo "tunnel $tunnel_id (port = ${listen_port}) is running: pid = $pids"
        fi
        let "i+=1"
    done

    if [ "" = "$proc_main" ]; then
        echo "sshfwd monitor is not running"
    else
        echo "sshfwd monitor is running: pid = $proc_main"
    fi

    echo ""
    echo "Local port listen info:"
    netstat -tunlp|grep LISTEN|grep tcp|grep -E "$pids_grep"
}


fn_run_monitor(){
    self_pid=$$
    pid1="dummy"`ps -ef|grep $self_pid|grep -v grep|awk '{printf "|%s",$2}'`
    pid2="dummy"`ps -ef|grep $self_pid|grep -v grep|awk '{printf "|%s",$3}'`
    pid3="dummy"`ps -ef|grep -E ""$pid1"|"$pid2"" |grep -v grep | awk '{printf "|%s",$2}'`
    pid_to_exclude=$pid1"|"$pid2"|"$pid3
    old_sshfwd_pid=`ps -ef|grep sshfwd|grep start|grep -vE "$pid_to_exclude"|grep -v grep|awk '{printf "%s ",$2}'`

    if [ "" = "$old_sshfwd_pid" ]; then
        echo "sshfwd monitor started successfully in background"
        while :
        do
            sleep $monitor_interval_secs
            fn_get_procs
            fn_start > /dev/null 2>&1
        done
    else
        echo "sshfwd monitor is already running: pid = $old_sshfwd_pid"
    fi
}

fn_print_usage() {
    echo "Usage: $0 <start|stop|restart|status>"
    return 2
}

case $1 in
    start)
    fn_start
    fn_run_monitor &
    # we must sleep 1 sec to make sure forked fn_run_monitor process can get its parent's process (the current process)
    sleep 1
    ;;
    stop)
    fn_stop_all
    ;;
    restart)
    fn_restart
    ;;
    status)
    fn_status
    ;;
    *)
    fn_print_usage
    ;;
esac

exit 0
