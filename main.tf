provider "aws" {
  region = "us-east-1"
}

data "aws_partition" "current" {}

resource "aws_iam_role" "test" {
  name               = "tf-acc-test-12345"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy" "AWSGlueServiceRole" {
  arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "test-AWSGlueServiceRole" {
  policy_arn = data.aws_iam_policy.AWSGlueServiceRole.arn
  role       = aws_iam_role.test.name
}

resource "aws_iam_role_policy" "LakeFormationDataAccess" {
  role = aws_iam_role.test.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LakeFormationDataAccess",
      "Effect": "Allow",
      "Action": [
        "lakeformation:GetDataAccess"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_vpc" "test" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "terraform-testacc-glue-connection-base"
  }
}

resource "aws_security_group" "test" {
  name   = "tf-acc-test-12345s"
  vpc_id = aws_vpc.test.id

  ingress {
    from_port = 1
    protocol  = "tcp"
    self      = true
    to_port   = 65535
  }
}

resource "aws_subnet" "test" {
  count = 5

  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = "10.0.${count.index}.0/24"
  vpc_id            = aws_vpc.test.id

  tags = {
    Name = "terraform-testacc-glue-connection-base"
  }
}

resource "aws_glue_catalog_database" "test" {
  name = "tf-acc-test-12345s"
}

resource "aws_glue_connection" "test" {
  connection_properties = {
    JDBC_ENFORCE_SSL = false
  }

  connection_type = "NETWORK"

  name = "tf-acc-test-12345s"

  physical_connection_requirements {
    availability_zone      = aws_subnet.test[0].availability_zone
    security_group_id_list = [aws_security_group.test.id]
    subnet_id              = aws_subnet.test[0].id
  }
}

resource "aws_glue_crawler" "test" {
  depends_on = [aws_iam_role_policy_attachment.test-AWSGlueServiceRole]

  database_name = aws_glue_catalog_database.test.name
  name          = "tf-acc-test-12345s"
  role          = aws_iam_role.test.name

  s3_target {
    connection_name = aws_glue_connection.test.name
    path            = "s3://bucket1"
  }
}
