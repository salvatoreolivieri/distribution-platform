environment            = "prod"
region                 = "eu-west-1"
vpc_cidr               = "10.30.0.0/16"
single_nat_gateway     = false
db_instance_class      = "db.t4g.small"
db_multi_az            = true
db_deletion_protection = true
web_origins            = ["https://docbridge.example.com"]
