#problem with conatiner definition not understand the exact concept of it"

# provider AWS


provider "aws" {
  access_key = "<your aws access keys>"
  secret_key = "<your aws secret keys>"
  region     = "us-east-2"
}

# create VPC

resource "aws_vpc" "mainvpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags {
    Name = "main-vpc"
  }
}

# create subnet for public network

resource "aws_subnet" "public-1" {
  vpc_id     = "${aws_vpc.mainvpc.id}"
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-2a"

  tags {
    Name = "public-1"
  }
}


resource "aws_subnet" "public-2" {
  vpc_id     = "${aws_vpc.mainvpc.id}"
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-2b"

  tags {
    Name = "public-2"
  }
}



# creating subnets for private network




resource "aws_subnet" "private-1" {
  vpc_id     = "${aws_vpc.mainvpc.id}"
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-2c"

  tags {
    Name = "private-1"
  }
}

resource "aws_subnet" "private-2" {
  vpc_id     = "${aws_vpc.mainvpc.id}"
  cidr_block = "10.0.4.0/24"
  availability_zone = "us-east-2c"

  tags {
    Name = "private-4"
  }
}

# creating gateway (public*2)



resource "aws_internet_gateway" "internet-gateway-1" {
  vpc_id = "${aws_vpc.mainvpc.id}"


  tags {
    Name = "internet-gateway-1"
  }
}

# routing tables


resource "aws_route_table" "routing-tables-1" {
  vpc_id = "${aws_vpc.mainvpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.internet-gateway-1.id}"
  }

#  tag {
#
#   Name  = "routing-tables-1"
#
#   }

}

# routing and association

resource "aws_route_table_association" "public-routing-2" {
  subnet_id      = "${aws_subnet.public-1.id}"
  route_table_id = "${aws_route_table.routing-tables-1.id}"
}

resource "aws_route_table_association" "routing-tables-3" {
  subnet_id      = "${aws_subnet.public-2.id}"
  route_table_id = "${aws_route_table.routing-tables-1.id}"
}

# EIP


resource "aws_eip" "eip" {

  vpc      = true
}

# NAT GATEWAY

resource "aws_nat_gateway" "nat-gateway" {
  allocation_id = "${aws_eip.eip.id}"
  subnet_id     = "${aws_subnet.public-1.id}"

  depends_on = ["aws_internet_gateway.internet-gateway-1"]

  tags {
    Name = "nat-gateway"
  }
}


# route table private

resource "aws_route_table" "routing-private" {
  vpc_id = "${aws_vpc.mainvpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.nat-gateway.id}"
  }

}
# routung private

resource "aws_route_table_association" "route-private-1" {
  subnet_id      = "${aws_subnet.private-1.id}"
  route_table_id = "${aws_route_table.routing-private.id}"
}

resource "aws_route_table_association" "route-private-2" {
  subnet_id      = "${aws_subnet.private-2.id}"
  route_table_id = "${aws_route_table.routing-private.id}"
}

### creating security group and open port 80 and 443

resource "aws_security_group" "security-group" {
  name        = "security-group-1"
  description = "controls access to the ALB"
  vpc_id      = "${aws_vpc.mainvpc.id}"


  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {
    protocol    = "tcp"
    from_port   = "443"
    to_port     = "443"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Traffic to the ECS cluster should only come from the ALB
resource "aws_security_group" "ecs_tasks" {
  name        = "cb-ecs-tasks-security-group"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${aws_vpc.mainvpc.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "80"
    to_port         = "80"
    security_groups = ["${aws_security_group.security-group.id}"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = "443"
    to_port     = "443"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### load balancer creation

resource "aws_alb" "loadbalancer" {

  name            = "load-balancer"
  subnets         = ["${aws_subnet.private-1.id}"]
  subnets         = ["${aws_subnet.private-2.id}"]

  security_groups = ["${aws_security_group.security-group.id}"]
}

resource "aws_alb_target_group" "loadbalancer-target-group" {
  name        = "loadbalancer-target-group"
  port        = "80"
  protocol    = "HTTP"
  vpc_id      = "${aws_vpc.mainvpc.id}"
  target_type = "ip"


}

# Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "loadbalancer-listner" {
  load_balancer_arn = "${aws_alb.loadbalancer.id}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.loadbalancer-target-group.id}"
    type             = "forward"
  }
}



# ecs.cluster

resource "aws_ecs_cluster" "ecs-cluster" {
  name = "ecs-cluster"

}

resource "aws_ecs_task_definition" "ecs-task-definition" {
  family                   = "app-task"
  execution_role_arn       = "${var.ecs_task_execution_role}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.fargate_cpu}"
  memory                   = "${var.fargate_memory}"


#container definition is causing problem to me..... ERROR is "Error: aws_ecs_task_definition.ecs-task-definition: "container_definitions": required field is not set"... dont know exact concept of it


  container_definitions    = ""
}

resource "aws_ecs_service" "ecs-service" {
  name            = "ecs-service"
  cluster         = "${aws_ecs_cluster.ecs-cluster.id}"
  task_definition = "${aws_ecs_task_definition.ecs-task-definition.arn}"
  desired_count   = "3"
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = ["${aws_security_group.security-group.id}"]
    subnets          = ["${aws_subnet.private-1.id}"]
    subnets          = ["${aws_subnet.private-1.id}"]

    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.loadbalancer-target-group.id}"
    container_name   = "nginx"
    container_port   = "80"
  }

  depends_on = ["aws_alb_listener.loadbalancer-listner",]
}

