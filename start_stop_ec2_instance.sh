#!/usr/bin/env bash
set -uo pipefail
aws_region="ap-south-1"

check_prerequisites(){
# is the aws CLI installed? are credentials valid?
   if ! command -v aws &> /dev/null; then
      echo "Error: AWS CLI is not installed." >&2
      echo "Install it: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
      exit 1
   fi
# Are the credentials configured and valid?

    if ! aws sts get-caller-identity &> /dev/null; then
        echo "Error: AWS credentials are missing or invaild." >&2
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
    local stopped instance_id current_state
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
         return 1
    fi
    current_state=$(get_state "$instance_id") || {
         echo "Instance $instance_id not found." >&2
         return 1
}

    case "$current_state" in
         running)  echo "Instance is already running."; return 0 ;;
         stopped)  ;;   # good, carry on and start it
         *)        echo "Instance is '$current_state'. Wait and try again."; return 1 ;;
    esac
    echo "Starting $instance_id..."
    aws ec2 start-instances --region "$aws_region" --instance-ids "$instance_id" > /dev/null
    aws ec2 wait instance-running --region "$aws_region" --instance-ids "$instance_id"
    echo "Instance $instance_id is now $(get_state "$instance_id")."

}
stop_instance() {
    local running instance_id current_state confirm

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
        return 1
    fi

    current_state=$(get_state "$instance_id") || {
        echo "Instance $instance_id not found." >&2
        return 1
    }

    case "$current_state" in
        stopped) echo "Instance is already stopped."; return 0 ;;
        running) ;;
        *)       echo "Instance is '$current_state'. Wait and try again."; return 1 ;;
    esac
    read -r -p "Are you sure you want to stop $instance_id? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Cancelled."; return 0; }
    echo "Stopping $instance_id..."
    aws ec2 stop-instances --region "$aws_region" --instance-ids "$instance_id" > /dev/null
    aws ec2 wait instance-stopped --region "$aws_region" --instance-ids "$instance_id"
    echo "Instance $instance_id is now $(get_state "$instance_id")."
}

check_prerequisites
while true;do

# A Menu driven EC2 instance start/stop/status script

    clear
    cat << EOF

Please select:
    1. Display the all instances (ID, Name, State) 
    2. Start an Instance.
    3. Stop an Instance.
    0. Quit

EOF

    read -r -p "Enter Option [0-3]:" option
    
    case $option in

        0) echo "Script Exited."; break ;;
        1) status_instance ;;
        2) start_instance ;; 
        3) stop_instance ;;
        *) echo "Invalid option." >&2 ;;

    esac
    read -r -p "Press Enter to continue.."

done
