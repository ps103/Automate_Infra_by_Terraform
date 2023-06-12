provider "aws" {
    region = "ap-south-1"
  
}

resource "aws_vpc" "my_vpc" {
  cidr_block       = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "My VPC"
  }
}
resource "aws_subnet" "subnet-1" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "ap-south-1a"
  tags = {
    Name = "subnet-1"
  }
}
resource "aws_subnet" "subnet-2" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1b"
  tags = {
    Name = "subnet-2"
  }
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "igw"
  }
}
resource "aws_route_table" "route" {
    vpc_id = aws_vpc.my_vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags = {
        Name = "route"
    }
}
resource "aws_route_table_association" "my_vpc_us_east_1a_public" {
    subnet_id = aws_subnet.subnet-1.id
    route_table_id = aws_route_table.route.id
}
resource "aws_route_table_association" "my_vpc_us_east_1b_public" {
    subnet_id = aws_subnet.subnet-2.id
    route_table_id = aws_route_table.route.id
}
 

 ## creating security group : -
 resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound connections"
  vpc_id = aws_vpc.my_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Allow HTTP Security Group"
  }
}

## creating launch configuration :-
resource "aws_launch_configuration" "web" {
  name_prefix = "web-"
  image_id = "ami-06f4bcea47497a780" 
  instance_type = "t2.micro"
  key_name = "mumbai1.key"
  security_groups = [ aws_security_group.allow_http.id ]
  associate_public_ip_address = true
 
  lifecycle {
    create_before_destroy = true
  }
}

## creating a load balancer :-

resource "aws_elb" "web_elb" {
  name = "web-elb"
  security_groups = [
    aws_security_group.allow_http.id
  ]
  subnets = [
    aws_subnet.subnet-1.id,
    aws_subnet.subnet-2.id
  ]
  cross_zone_load_balancing   = true
  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:80/"
  }
  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "80"
    instance_protocol = "http"
  }
}

## Creating a auto scaling group :- 

resource "aws_autoscaling_group" "web" {
  name = "${aws_launch_configuration.web.name}-asg"
  min_size             = 1
  desired_capacity     = 2
  max_size             = 4
  
  health_check_type    = "ELB"
  load_balancers = [
    aws_elb.web_elb.id
  ]
  launch_configuration = aws_launch_configuration.web.name
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]
  metrics_granularity = "1Minute"
  vpc_zone_identifier  = [
    aws_subnet.subnet-1.id,
    aws_subnet.subnet-2.id
  ]
  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }
  tag {
    key                 = "Name"
    value               = "web"
    propagate_at_launch = true
  }
}
## auto scaling policy :-
resource "aws_autoscaling_policy" "web_policy_up" {
  name = "web_policy_up"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}
resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_up" {
  alarm_name = "web_cpu_alarm_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "60"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }
  alarm_description = "This metric monitor EC2 instance CPU utilization"
  alarm_actions = [ aws_autoscaling_policy.web_policy_up.arn ]
}

