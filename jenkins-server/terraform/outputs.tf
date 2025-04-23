locals {
  default_users = {
    "ubuntu"        = "ubuntu"
    "amazon"        = "ec2-user"
    "centos"        = "centos"
    "debian"        = "admin"
    "rhel"          = "ec2-user"
    "suse"          = "ec2-user"
    "al2023"        = "ec2-user"
  }

  ami_name = data.aws_ami.Amazon_AMI.name

  ec2_default_user = (
    contains(local.ami_name, "ubuntu") ? local.default_users["ubuntu"] :
    contains(local.ami_name, "amzn")   ? local.default_users["amazon"] :
    contains(local.ami_name, "centos") ? local.default_users["centos"] :
    contains(local.ami_name, "debian") ? local.default_users["debian"] :
    contains(local.ami_name, "rhel")   ? local.default_users["rhel"] :
    contains(local.ami_name, "suse")   ? local.default_users["suse"] :
    contains(local.ami_name, "al2023") ? local.default_users["al2023"] :
    "ubuntu"
  )
}

output "jenkins_instance_public_ip" {
  value = aws_instance.jenkins_instance.public_ip
}

output "ssh_connection_string" {
  value = "ssh -i ~/.ssh/${var.key_pair_name}.pem ${local.ec2_default_user}@${aws_instance.jenkins_instance.public_ip}"
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins_instance.public_ip}:8080"
}