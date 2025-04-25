# Replace with your actual GCP project ID
project_id = "dataeng-456707"

# Region and zone
region = "us-west1"
zone   = "us-west1-a"

# VM configuration
machine_type = "e2-medium"
vm_name      = "busdata-pipeline-vm"

# GitHub repository information
github_repo = "https://github.com/boblancer/busdata-pipeline"
github_branch = "main"

# List of vehicle IDs to collect data for
vehicle_ids = [
  "VEHICLE_ID_1", 
  "VEHICLE_ID_2", 
  "VEHICLE_ID_3"
]

# Your SSH public key as a string (optional)
# Example: "ssh-rsa AAAAB3NzaC1yc2EA... user@example.com"
ssh_public_key = ""