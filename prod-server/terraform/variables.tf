variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  default = "10.0.1.0/24"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "key_pair_name" {
  description = "AWS key pair name to access the instance"
  type        = string
}

variable "public_key_path" {
  description = "Path to public SSH key file"
  type        = string
}

variable "private_key_path" {
  description = "Path to private SSH key file (for output)"
  type        = string
}