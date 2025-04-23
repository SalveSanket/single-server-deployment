locals {
  # Determine the default SSH user based on the AMI name pattern
  ami_name = data.aws_ami.ubuntu.name

  ssh_user = (
    can(regex("ubuntu", local.ami_name))  ? "ubuntu"    :
    can(regex("amzn", local.ami_name))    ? "ec2-user"  :
    can(regex("centos", local.ami_name))  ? "centos"    :
    can(regex("debian", local.ami_name))  ? "admin"     :
    can(regex("rhel", local.ami_name))    ? "ec2-user"  :
    can(regex("suse", local.ami_name))    ? "ec2-user"  :
    "ubuntu" # fallback
  )
}

output "prodserver_public_ip" {
  description = "Public IP address of the prodserver EC2 instance"
  value       = aws_instance.prodserver_instance.public_ip
}

output "prodserver_url" {
  description = "URL to access the application running on prodserver"
  value       = "http://${aws_instance.prodserver_instance.public_ip}:5000"
}

output "default_ssh_user" {
  description = "Default SSH username derived from AMI type"
  value       = local.ssh_user
}

output "ssh_connection_command" {
  description = "SSH command to connect to the prodserver instance"
  value       = "ssh -i ${var.private_key_path} ${local.ssh_user}@${aws_instance.prodserver_instance.public_ip}"
}