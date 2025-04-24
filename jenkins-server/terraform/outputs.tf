
locals {
  # Mapping of AMI types to default SSH usernames
  default_users = {
    "ubuntu"  = "ubuntu"
    "amzn"    = "ec2-user"
    "centos"  = "centos"
    "debian"  = "admin"
    "rhel"    = "ec2-user"
    "suse"    = "ec2-user"
    "al2023"  = "ec2-user"
  }

  # AMI name fetched from the AMI data source
  ami_name = data.aws_ami.Amazon_AMI.name

  # Determine the appropriate username based on AMI name
  ec2_default_user = (
    can(regex("ubuntu", local.ami_name))  ? local.default_users["ubuntu"]  :
    can(regex("amzn", local.ami_name))    ? local.default_users["amzn"]    :
    can(regex("centos", local.ami_name))  ? local.default_users["centos"]  :
    can(regex("debian", local.ami_name))  ? local.default_users["debian"]  :
    can(regex("rhel", local.ami_name))    ? local.default_users["rhel"]    :
    can(regex("suse", local.ami_name))    ? local.default_users["suse"]    :
    can(regex("al2023", local.ami_name))  ? local.default_users["al2023"]  :
    "ubuntu" # Default fallback
  )
}

# Output the AMI name and default SSH username
output "jenkins_instance_public_ip" {
  description = "Public IP address of the Jenkins EC2 instance"
  value       = aws_instance.jenkins_instance.public_ip
}
output "default_ec2_username" {
  description = "Default SSH username based on AMI type"
  value       = local.ec2_default_user
}

output "ssh_connection_string" {
  description = "SSH command to access the Jenkins server"
  value       = "ssh -i ${var.private_key_file} ${local.ec2_default_user}@${aws_instance.jenkins_instance.public_ip}"
}

output "jenkins_url" {
  description = "Jenkins Web UI URL"
  value       = "http://${aws_instance.jenkins_instance.public_ip}:8080"
}

output "private_key_file" {
  description = "Path to the private key used for SSH"
  value       = var.private_key_file
}