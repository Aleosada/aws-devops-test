##################################################################################
# CONFIGURATION (for Terraform > 0.12)
##################################################################################

terraform {
  backend "s3" {
    bucket = "infra-tfstate-27991"
    key    = "networking/vpc/terraform-state"
    region = "us-east-1"
    dynamodb_table = "infra-tfstatelock-27991"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  region = var.region
}

##########################################################################
# DATA
##########################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

##########################################################################
# RESOURCES
##########################################################################

resource "aws_vpc" "web-vpc" {
  cidr_block = var.web_network_address_space[terraform.workspace]
  assign_generated_ipv6_cidr_block = true
  tags = merge({ Name = "web-vpc" }, local.common_tags)
}

resource "aws_iam_role" "flowlogs-role" {
  name = "flowlogs-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "flowlogs-role-policy" {
  name = "flowlogs-role-policy"
  role = aws_iam_role.flowlogs-role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_log_group" "flowlog" {
  name = "flowlog"
  tags = local.common_tags
}

resource "aws_flow_log" "web-vpc-flowlogs-accepted" {
  iam_role_arn    = aws_iam_role.flowlogs-role.arn
  log_destination = aws_cloudwatch_log_group.flowlog.arn
  traffic_type    = "ACCEPT"
  vpc_id          = aws_vpc.web-vpc.id
  tags = local.common_tags
}

resource "aws_flow_log" "web-vpc-flowlogs-rejected" {
  iam_role_arn    = aws_iam_role.flowlogs-role.arn
  log_destination = aws_cloudwatch_log_group.flowlog.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.web-vpc.id
  tags = local.common_tags
}

resource "aws_subnet" "web-subnet" {
  count      = var.web_subnet_count[terraform.workspace]
  vpc_id     = aws_vpc.web-vpc.id
  cidr_block = cidrsubnet(var.web_network_address_space[terraform.workspace], 8, count.index % var.web_subnet_count[terraform.workspace])
  ipv6_cidr_block = cidrsubnet(aws_vpc.web-vpc.ipv6_cidr_block, 8, count.index % var.web_subnet_count[terraform.workspace])
  availability_zone = data.aws_availability_zones.available.names[count.index % var.web_subnet_count[terraform.workspace]]

  tags = merge({ Name = "web-subnet-${count.index}" }, local.common_tags)
}

resource "aws_internet_gateway" "web-igw" {
  vpc_id = aws_vpc.web-vpc.id

  tags = merge({ Name = "web-igw" }, local.common_tags)
}

resource "aws_route_table" "web-rtb" {
  vpc_id = aws_vpc.web-vpc.id

  tags = merge({ Name = "web-rtb" }, local.common_tags)
}

resource "aws_route" "web-route-igw" {
  route_table_id            = aws_route_table.web-rtb.id
  destination_cidr_block    = "0.0.0.0/"
  gateway_id                = aws_internet_gateway.web-igw.id
}

resource "aws_route" "web-route-igw-ipv6" {
  route_table_id            = aws_route_table.web-rtb.id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                = aws_internet_gateway.web-igw.id
}

resource "aws_route" "route-web-shared" {
  route_table_id            = aws_route_table.web-rtb.id
  destination_cidr_block    = var.shared_network_address_space[terraform.workspace]
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_peering_shared_web.id
}

resource "aws_route_table_association" "rta-subnet" {
  count          = var.web_subnet_count[terraform.workspace]
  subnet_id      = aws_subnet.web-subnet[count.index % var.web_subnet_count[terraform.workspace]].id
  route_table_id = aws_route_table.web-rtb.id
}
