terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-south-1"
}

#VPC
resource "aws_vpc" "VPC2" {
  cidr_block = "20.0.0.0/16"

  tags = {
    Name = "VPC2"
  }
}

#Subnets
resource "aws_subnet" "VPC2_subnet1" {
  vpc_id                  = aws_vpc.VPC2.id
  cidr_block              = "20.0.0.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "VPC2_subnet1"
  }
}

resource "aws_subnet" "VPC2_subnet2" {
  vpc_id                  = aws_vpc.VPC2.id
  cidr_block              = "20.0.3.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "VPC2_subnet2"
  }
}

#Security Groups
resource "aws_security_group" "Three_Tier_sg" {
  vpc_id = aws_vpc.VPC2.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Three_Tier_SG"
  }
}

resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.VPC2.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ALB-SG"
  }
}

resource "aws_security_group" "RDS_sg" {
  vpc_id = aws_vpc.VPC2.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.Three_Tier_sg.id]
  }


  tags = {
    Name = "RDS-SG"
  }
}

#Launch Template
resource "aws_launch_template" "Three_Tier_Launch_Template" {
  name = "3-Tier-Launch-Template"
  image_id = "ami-03eb24e9030ab6360"
  instance_type = "t3.micro"
  key_name = "AWS-Keypair-2"

  
  user_data = base64encode(<<-EOF
            #!/bin/bash
            cd /home/ubuntu/aws-rds-java/src/main/webapp/
            sudo sed -i "s#jdbc:mysql://database-1.cv8cisoqaphe.ap-south-1.rds.amazonaws.com:3306#${aws_db_instance.RDS-Instance.endpoint}#" userRegistration.jsp

            sudo sed -i "s#jdbc:mysql://database-1.cv8cisoqaphe.ap-south-1.rds.amazonaws.com:3306#${aws_db_instance.RDS-Instance.endpoint}#" login.jsp

            cd
            cd aws-rds-java
            sudo mvn clean package
            sudo mv target/LoginWebApp.war /var/lib/tomcat10/webapps/ROOT.war
            sudo systemctl restart tomcat10
            sudo systemctl enable tomcat10
            EOF
)


  network_interfaces {
    associate_public_ip_address = false
    security_groups = [aws_security_group.Three_Tier_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "MyInstance"
    }
  }
}

#ASG
resource "aws_autoscaling_group" "example" {
  desired_capacity = 2
  max_size = 3
  min_size = 1
  vpc_zone_identifier  = [aws_subnet.VPC2_subnet1.id]

  launch_template {
    id      = aws_launch_template.Three_Tier_Launch_Template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "MyASGInstance"
    propagate_at_launch = true
  }
}

#ALB
resource "aws_lb" "Three_Tier_ALB" {
  name               = "Three-Tier-ALB"
  load_balancer_type = "application"
  subnets            = [aws_subnet.VPC2_subnet1.id,aws_subnet.VPC2_subnet2.id]
  security_groups    = [aws_security_group.Three_Tier_sg.id]
  internal           = false
  tags = {
    Name = "Three_Tier_ALB"
  }
}

resource "aws_lb_target_group" "target-group-three-tier1" {
  name     = "target-group-three-tier1"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.VPC2.id
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.example.name
  alb_target_group_arn = aws_lb_target_group.target-group-three-tier1.arn
}



resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.Three_Tier_ALB.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target-group-three-tier1.arn
  }
}

#RDS

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.VPC2_subnet1.id, aws_subnet.VPC2_subnet2.id]

  tags = {
    Name = "RDS-Subnet-Group"
  }
}

resource "aws_db_instance" "RDS-Instance" {
  allocated_storage = 20
  storage_type = "gp2"
  engine = "mysql"
  engine_version = "5.7"
  instance_class = "db.t3.micro"
  identifier = "mydb"
  username = "admin"
  password = "Saksham17"

  vpc_security_group_ids  = [aws_security_group.RDS_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  skip_final_snapshot = true
}

output "rds-endpoint" {
  value = aws_db_instance.RDS-Instance.endpoint
}

