# This Terraform configuration file sets up a Jenkins server on AWS.
# It creates a VPC, an Internet Gateway, a public subnet, a security group,
# and an EC2 instance for Jenkins.
# It also configures the necessary routes and security group rules for SSH and HTTP access.

# Configure AWS VPC
resource "aws_vpc" "jenkins_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "Jenkins VPC"
  }
}

# Create an Internet Gateway and attach it to the VPC
resource "aws_internet_gateway" "jenkins_igw" {
  vpc_id = aws_vpc.jenkins_vpc.id
  tags = {
    Name = "Jenkins Internet Gateway"
  }
}

# Create a public subnet in the VPC
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.jenkins_vpc.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone
}

# Create a route table for the public subnet and associate it with the Internet Gateway
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.jenkins_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.jenkins_igw.id
  }
  tags = {
    Name = "Jenkins Public Route Table"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Create a security group for the Jenkins server
resource "aws_security_group" "jenkins_sg" {
  vpc_id      = aws_vpc.jenkins_vpc.id
  name        = "jenkins_sg"
  description = "Security group for Jenkins server"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.http_ingress_cidr]
    description = "Allow HTTP traffic"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
    description = "Allow SSH traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "Jenkins Security Group"
  }
}

# Create an SSH key pair for accessing the Jenkins server
# Note: Ensure the public key file exists at the specified path
resource "aws_key_pair" "jenkins_key" {
  key_name   = var.key_pair_name
  public_key = file(var.public_key_path)
}

# Create an EC2 instance for Jenkins server
resource "aws_instance" "jenkins_instance" {
  ami                    = data.aws_ami.Amazon_AMI.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  key_name               = aws_key_pair.jenkins_key.key_name

  tags = {
    Name = "Jenkins Server"
  }
}