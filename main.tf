terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.51.0"
    }
  }
}

# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Variables
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  default     = "us-west1"
  type        = string
}

variable "zone" {
  description = "The GCP zone"
  default     = "us-west1-a"
  type        = string
}

variable "machine_type" {
  description = "The machine type for the VM instance"
  default     = "e2-medium"
  type        = string
}

variable "vm_name" {
  description = "Name for the VM instance"
  default     = "busdata-collector-vm"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository URL"
  type        = string
  default     = "https://github.com/boblancer/busdata-pipeline"
}

variable "github_branch" {
  description = "GitHub branch to use"
  type        = string
  default     = "main"
}

variable "vehicle_ids" {
  description = "List of vehicle IDs to collect data for"
  type        = list(string)
  default     = ["VEHICLE_ID_1", "VEHICLE_ID_2", "VEHICLE_ID_3"]
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  default     = ""  # Provide your public key as a string in terraform.tfvars instead of reading from file
}

# Create a VPC network
resource "google_compute_network" "vpc_network" {
  name                    = "busdata-network"
  auto_create_subnetworks = true
}

# Create a firewall rule to allow SSH
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Create a VM instance
resource "google_compute_instance" "vm_instance" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
    }
  }

  resource_policies = [google_compute_resource_policy.daily_vm_schedule.self_link]

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
      // Ephemeral public IP
    }
  }

  # Only add SSH keys if provided
  metadata = {
    ssh-keys = var.ssh_public_key != "" ? "debian:${var.ssh_public_key}" : null
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -x
    apt-get update
    apt-get install -y python3-pip curl git
    pip3 install google-cloud-pubsub
    pip3 install requests

    # Set timezone to Pacific
    timedatectl set-timezone America/Los_Angeles
    
    # Create directory for the project
    mkdir -p /opt/busdata
    mkdir -p /opt/busdata/raw_data
    
    # Clone the GitHub repository
    git clone -b ${var.github_branch} ${var.github_repo} /tmp/busdata-repo
    
    # Copy scripts from the repository to the working directory
    cp /tmp/busdata-repo/data_collector.py /opt/busdata/data_collector.py
    chmod +x /opt/busdata/data_collector.py

    cp /tmp/busdata-repo/ids.txt /opt/busdata/ids.txt
    chmod 644 /opt/busdata/ids.txt   
    
    # Run the script once during setup to verify it works
    cd /opt/busdata && python3 data_collector.py > /opt/busdata/initial_run.log 2>&1
  EOF

  service_account {
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# Create Pub/Sub topic for breadcrumb data
resource "google_pubsub_topic" "breadcrumb_topic" {
  name = "breadcrumb-data-topic"
}

# Create Pub/Sub subscription for the breadcrumb data
resource "google_pubsub_subscription" "breadcrumb_subscription" {
  name  = "breadcrumb-data-subscription"
  topic = google_pubsub_topic.breadcrumb_topic.name

  # Set the acknowledgement deadline to 60 seconds
  ack_deadline_seconds = 60

  # Set the message retention duration to 7 days
  message_retention_duration = "604800s"

  # Enable message ordering if neededƒ
  enable_message_ordering = false

  # Configure retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Set expiration policy to never expire
  expiration_policy {
    ttl = ""
  }
}

# Optional: Create a second VM for the subscriber (for extra credit)
resource "google_compute_instance" "subscriber_vm" {
  name         = "busdata-subscriber-vm"
  machine_type = "e2-small"  # Using a smaller instance for the subscriber
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
    }
  }

  resource_policies = [google_compute_resource_policy.daily_vm_schedule.self_link]

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
      // Ephemeral public IP
    }
  }

  # Only add SSH keys if provided
  metadata = {
    ssh-keys = var.ssh_public_key != "" ? "debian:${var.ssh_public_key}" : null
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -x
    apt-get update
    apt-get install -y python3-pip git
    pip3 install google-cloud-pubsub
    
    # Set timezone to Pacific
    timedatectl set-timezone America/Los_Angeles
    
    # Create directory for the project
    mkdir -p /opt/busdata/output
    
    # Clone the GitHub repository
    git clone -b ${var.github_branch} ${var.github_repo} /tmp/busdata-repo
    
    # Copy scripts from the repository to the working directory
    cp /tmp/busdata-repo/data_subscriber.py /opt/busdata/data_subscriber.py
    cp /tmp/busdata-repo/ids.txt /opt/busdata/ids.txt     # Added this line to copy ids.txt
    chmod +x /opt/busdata/data_subscriber.py
    chmod 644 /opt/busdata/ids.txt      
    
    [Unit]
    Description=TriMet Bus Data Subscriber Service
    After=network.target

    [Service]
    Type=simple
    User=root
    WorkingDirectory=/opt/busdata
    ExecStart=/usr/bin/python3 /opt/busdata/data_subscriber.py
    Restart=always
    RestartSec=10

    [Install]
    WantedBy=multi-user.target
    END

    systemctl daemon-reload
    systemctl enable busdata-subscriber.service
    systemctl start busdata-subscriber.service
  EOF

  service_account {
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# Schedule VM to start and stop automatically
resource "google_compute_resource_policy" "daily_vm_schedule" {
  name   = "vm-start-stop-schedule"
  region = var.region
  
  instance_schedule_policy {
    vm_start_schedule {
      schedule = "0 8 * * *"  # Start VM at 8:00
    }
    
    # When to stop the VM (in cron format) - 30 minutes later
    vm_stop_schedule {
      schedule = "30 8 * * *"  # Stop VM at 8:30 
    }
    
    time_zone = "America/Los_Angeles"
  }
}

# Output the VM's external IP
output "vm_external_ip" {
  value = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
}

# Output the subscriber VM's external IP
output "subscriber_vm_external_ip" {
  value = google_compute_instance.subscriber_vm.network_interface[0].access_config[0].nat_ip
}

# Output the Pub/Sub topic name
output "pubsub_topic_name" {
  value = google_pubsub_topic.breadcrumb_topic.name
}

# Output the Pub/Sub subscription name
output "pubsub_subscription_name" {
  value = google_pubsub_subscription.breadcrumb_subscription.name
}