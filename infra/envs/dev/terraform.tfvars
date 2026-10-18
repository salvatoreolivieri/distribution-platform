environment        = "dev"
region             = "eu-west-1"
single_nat_gateway = true
db_instance_class  = "db.t4g.micro"
db_multi_az        = false
web_origins        = ["http://localhost:5173"]
log_level          = "debug"
