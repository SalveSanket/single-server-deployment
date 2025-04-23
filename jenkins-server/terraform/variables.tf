variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone for the public subnet"
  default     = "us-east-1a"
}

variable "ssh_ingress_cidr" {
  description = "CIDR block allowed to access via SSH"
  default     = "0.0.0.0/0"
}

variable "http_ingress_cidr" {
  description = "CIDR block allowed to access Jenkins UI"
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.medium"
}

variable "key_pair_name" {
  description = "Name of the SSH key pair"
  default     = "jenkins-key"
}

variable "public_key_path" {
  description = "Path to the SSH public key"
  default     = "~/.ssh/jenkinsServerKey.pub"
}

variable "private_key_file" {
  description = "Path to the private SSH key used for EC2 connection"
  type        = string
}