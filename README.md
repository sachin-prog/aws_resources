This Repo for AWS Resources creation,updation.Remove from AWS Account 
# EC2 Instance Manager (Bash)

A menu-driven Bash script to list, start and stop AWS EC2 instances using the AWS CLI.

It is built with safety in mind: it checks prerequisites before running, validates input, verifies an instance's current state before acting on it, asks for confirmation before stopping, and only reports success once AWS confirms the state change.

## Features

- **List instances**: shows the Instance ID, Name tag, State and Availability Zone in a table
- **Start an instance**: lists stopped instances, then starts the one you choose and waits until it is `running`
- **Stop an instance**: lists running instances, asks for confirmation, then stops the one you choose and waits until it is `stopped`
- **Prerequisite checks**: verifies the AWS CLI is installed and the credentials are valid before showing the menu
- **Input validation**: rejects empty or malformed instance IDs before calling AWS
- **State checks**: won't start an instance that's already running or stop one that's already stopped, and handles transitional states (`pending`, `stopping`)
- ** Know Public Ip Address ** : Shows the Public ip address

## Prerequisites

- Bash 4+
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- AWS credentials configured with `aws configure`

### Required IAM permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:StartInstances",
        "ec2:StopInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

`sts:GetCallerIdentity`, used for the credential check, doesn't need any permission.

## Usage

```bash
git clone git@github.com:sachin-prog/aws_resources.git
cd aws_resources
chmod +x start_stop_ec2_instance.sh
./start_stop_ec2_instance.sh
```

The region defaults to `ap-south-1` (Mumbai). To use another region, change `aws_region` at the top of the script.

### Menu

```
Please select:
    1. Display all instances (ID, Name, State)
    2. Start an instance
    3. Stop an instance
    0. Quit

Enter Option [0-3]:
```

### Sample output

```
------------------------------------------------------------------
|                        DescribeInstances                       |
+-------------+-----------------------+-------------+-----------+
|     AZ      |          ID           |    Name     |   State   |
+-------------+-----------------------+-------------+-----------+
|  ap-south-1a|  i-0a1b2c3d4e5f67890  |  web-server |  running  |
|  ap-south-1b|  i-0f9e8d7c6b5a43210  |  dev-box    |  stopped  |
+-------------+-----------------------+-------------+-----------+
```

## How it works

| Function | Purpose |
|---|---|
| `check_prerequisites` | Checks the AWS CLI with `command -v aws` and the credentials with `aws sts get-caller-identity` |
| `status_instance` | Calls `describe-instances` and shapes the output with a JMESPath `--query` |
| `get_state` | Returns the current state of one instance, or fails if the ID doesn't exist |
| `validate_instance_id` | Checks that the ID matches `^i-[0-9a-f]+$` |
| `start_instance` / `stop_instance` | List candidates, validate the chosen ID, check its state, act on it, then `aws ec2 wait` for completion |

Key design choices:

- **`set -uo pipefail`**: catches unset variables and failures inside pipes. `-e` is left out on purpose, so a single failed AWS call returns you to the menu instead of killing the script. Errors are handled explicitly with `if` and `||`.
- **`aws ec2 wait`**: polls AWS until the instance reaches its target state, so the script only reports success once the change is real.
- **Validation before API calls**: bad input fails fast with a clear message.

## Possible improvements

- Command-line arguments (for example `./script.sh stop i-0abc...`) for use in cron or CI pipelines
- `--region` and `--profile` flags
- Start or stop instances by tag (for example `Environment=dev`) for cost savings
- Log actions with timestamps
- A scheduled Lambda + EventBridge version to stop dev instances automatically at night

## Author

Sachin Gupta, [github.com/sachin-prog](https://github.com/sachin-prog) 
