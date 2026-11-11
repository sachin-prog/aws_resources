#!/usr/bin/env bash
set -uo pipefail
aws_region="ap-south-1"
log_file="$HOME/ec2_manager.log"
log(){
    local level="$1"; shift
    printf '%s [%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$USER" "$*" >> "$log_file"

}
check_prerequisites(){
# is the aws CLI installed? are credentials valid?
   if ! command -v aws &> /dev/null; then
      echo "Error: AWS CLI is not installed." >&2
      echo "Install it: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
      exit 1
   fi
# Are the credentials configured and valid?

    if ! aws sts get-caller-identity &> /dev/null; then
        echo "Error: AWS credentials are missing or invalid." >&2
        echo "Run aws configure to set them up" >&2
        exit 1
    fi

} 
status_instance(){
    aws ec2 describe-instances \
        --region "$aws_region" \
        --query 'Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,AZ:Placement.AvailabilityZone}' \
        --output table

}
get_state(){
# helper: return the current state of one instance id
    local instance_id="$1"
    local state
    if ! state=$(aws ec2 describe-instances \
            --region "$aws_region" \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null); then
        echo "Invalid"
        return 1
    fi

    echo "$state"
}
validate_instance_id() {
    local id="$1"
    [[ -n "$id" && "$id" =~ ^i-[0-9a-f]+$ ]]
}

start_instance(){
    local stopped instance_id current_state final_state
    stopped=$(aws ec2 describe-instances \
        --region "$aws_region" \
        --filters "Name=instance-state-name,Values=stopped" \
        --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`]|[0].Value]' \
        --output text)

    if [[ -z "$stopped" ]]; then
        echo "No Stopped instances in $aws_region."
        return 0
    fi

    echo "Stopped Instances:"

    echo "$stopped"

    read -r -p "Enter instance ID: " instance_id

    if ! validate_instance_id "$instance_id"; then
        echo "Invalid instance ID." >&2
        log ERROR "Invalid instance ID entered: '$instance_id'"
        return 1
    fi
    current_state=$(get_state "$instance_id") || {
        echo "Instance $instance_id not found." >&2
        log ERROR "Instance not found: $instance_id"
        return 1
}

    case "$current_state" in
        running)  echo "Instance is already running."; return 0 ;;
        stopped)  ;;   # good, carry on and start it
        *)        echo "Instance is '$current_state'. Wait and try again."; return 1 ;;
    esac
    echo "Starting $instance_id..."
    log INFO "Start requested: $instance_id"
    if ! aws ec2 start-instances --region "$aws_region" --instance-ids "$instance_id" > /dev/null; then
        echo "Failed to start $instance_id." >&2
        log ERROR "start-instances failed: $instance_id"
        return 1
    fi
    if ! aws ec2 wait instance-running --region "$aws_region" --instance-ids "$instance_id" > /dev/null; then
        echo "Timed out waiting for $instance_id to start." >&2
        log ERROR "wait instance-start timed out: $instance_id"
        return 1
    fi    
    final_state=$(get_state "$instance_id")
    log INFO "$instance_id is now $final_state"
    echo "Instance $instance_id is now $final_state."

}
know_ip_instance(){

    local running 
    running=$(aws ec2 describe-instances \
        --region "$aws_region" \
        --filters "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].[InstanceId,Tags[?Key=='Name']|[0].Value, PublicIpAddress]' \
        --output text)

    if [[ -z "$running" ]]; then
        echo " No running instances in $aws_region."
        return 0
    fi

    echo " Running Instances Public IP Address:"
    printf " %-22s %-25s %-16s\n" "INSTANCE ID" "NAME" "PUBLIC IP"
    printf " %-22s %-25s %-16s\n" "-----------" "----" "---------"

    while read -r instance_id name pub_ip_address; do
        [[ "$name" == "None" ]] && name="-"
        [[ "$pub_ip_address" == "None" ]] && pub_ip_address="(no public IP)"
        printf " %-22s %-25s %-16s\n" "$instance_id" "$name" "$pub_ip_address"
    done <<< "$running"
}
stop_instance() {
    local running instance_id current_state confirm final_state

    running=$(aws ec2 describe-instances \
        --region "$aws_region" \
        --filters "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`]|[0].Value]' \
        --output text)

    if [[ -z "$running" ]]; then
        echo "No running instances in $aws_region."
        return 0
    fi

    echo "Running instances:"
    echo "$running"

    read -r -p "Enter instance ID: " instance_id

    if ! validate_instance_id "$instance_id"; then
        echo "Invalid instance ID." >&2
        log ERROR "Invalid instance ID entered: '$instance_id'"
        return 1
    fi

    current_state=$(get_state "$instance_id") || {
        echo "Instance $instance_id not found." >&2
        log ERROR "Instance not found: $instance_id"
        return 1
    }

    case "$current_state" in
        stopped) echo "Instance is already stopped."; return 0 ;;
        running) ;;
        *)       echo "Instance is '$current_state'. Wait and try again."; return 1 ;;
    esac
    read -r -p "Are you sure you want to stop $instance_id? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Cancelled."; log WARN "Stop cancelled by user: $instance_id"; return 0; }
    echo "Stopping $instance_id..."
    log INFO "Stop requested: $instance_id"
    
    if ! aws ec2 stop-instances --region "$aws_region" --instance-ids "$instance_id" > /dev/null; then
        echo "Failed to Stop $instance_id." >&2
        log ERROR "stop-instance failed: $instance_id"
        return 1
    fi    
    if ! aws ec2 wait instance-stopped --region "$aws_region" --instance-ids "$instance_id"; then
        echo "Timed out waiting for $instance_id to stop." >&2
        log ERROR "wait instance-stopped timed out: $instance_id"
        return 1
    fi
    
    final_state=$(get_state "$instance_id")
    log INFO "$instance_id is now $final_state"
    echo "Instance $instance_id is now $final_state."
}

check_prerequisites
log INFO "Script started (region: $aws_region)"
while true;do

# A Menu driven EC2 instance start/stop/status script

    clear
    cat << EOF

Please select:
    1. Display all instances (ID, Name, State) 
    2. Start an Instance.
    3. Stop an Instance.
    4. Know PublicIPAddress.
    0. Quit

EOF

    read -r -p "Enter Option [0-4]:" option
    
    case "$option" in

        0) echo "Script Exited."; log INFO "Script exited"; break ;;
        1) status_instance ;;
        2) start_instance ;; 
        3) stop_instance ;;
        4) know_ip_instance ;;
        *) echo "Invalid option." >&2 ;;

    esac
    read -r -p "Press Enter to continue.."

done
