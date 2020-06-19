provider "aws"{
	region = "ap-south-1"
	profile= "default"
}

//creating private key
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
}

//generates key_value pair
resource "aws_key_pair" "sd_key" {
  key_name   = "task1_sd"
  public_key = tls_private_key.private_key.public_key_openssh

  depends_on = [
    tls_private_key.private_key
  ]
}

//save private key in pem file 
resource "local_file" "key-file" {
  content  = tls_private_key.private_key.private_key_pem
  filename = "task1_sd_key.pem"

  depends_on = [
    tls_private_key.private_key
  ]
}

//create security group
resource "aws_security_group" "aws_security" {
  name        = "aws_security"
 
  //allowing ssh through 22 port number
  ingress {
    description = "SSH Rule"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  //allowing HTTP through 80 port number
  ingress {
    description = "HTTP Rule"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



//create variable ami 
variable "ami_id1"{
	type = string
	default ="ami-0447a12f28fddb066"
}
resource "aws_instance" "instance_sd" {
  ami           = var.ami_id1
  instance_type = "t2.micro"
  key_name = aws_key_pair.sd_key.key_name
  security_groups = ["${aws_security_group.aws_security.name}","default"]

  tags = {
    Name = "task1_instance_sd"
  }

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.private_key.private_key_pem
    host     = aws_instance.instance_sd.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
}



//create ebs volume as a pendrive of 1gib
resource "aws_ebs_volume" "ebs_vol" {
  availability_zone = aws_instance.instance_sd.availability_zone
  size              = 1
  tags = {
    Name = "task1_vol"
  }
}
resource "aws_volume_attachment" "ebs_att_sd" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.ebs_vol.id}"
  instance_id = "${aws_instance.instance_sd.id}"
  force_detach = true
}




//interaction in launched instace os to performming tasks
resource "null_resource" "null_res_1"  {
  depends_on = [
    aws_volume_attachment.ebs_att_sd,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.private_key.private_key_pem
    host     = aws_instance.instance_sd.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/sd217/aws_terraform.git /var/www/html/"
    ]
  }
}



//create bucket in s3 
resource "aws_s3_bucket" "s3_buck_sd" {
depends_on = [
    null_resource.null_res_1
  ]
  bucket = "sd-task1-bucket"
  acl    = "public-read"

  tags = {
    Name        = "SD bucket"
  }
}

//created s3 bucket store image
resource "aws_s3_bucket_object" "s3_buck_sd_obj1" {
  key    = "image1.png"
  bucket = "${aws_s3_bucket.s3_buck_sd.bucket}"
  source = "image1.png"
  acl = "public-read"

  force_destroy = true
}


resource "aws_s3_bucket_object" "s3_buck_sd_obj2" {

  key    = "image2.jpeg"
  bucket = "${aws_s3_bucket.s3_buck_sd.bucket}"
  source = "shardul.jpeg"
  acl = "public-read"

  force_destroy = true
}

//cloudfront_distrubution creating
resource "aws_cloudfront_distribution" "sd_cf" {
depends_on = [
    aws_s3_bucket_object.s3_buck_sd_obj2
  ]
  origin {
    domain_name = "${aws_s3_bucket.s3_buck_sd.bucket_regional_domain_name}"
    origin_id   = "${aws_s3_bucket.s3_buck_sd.id}"
  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "S3 storage Distribution"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${aws_s3_bucket.s3_buck_sd.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

   viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }

  tags = {
    Name        = "sd_cf_Distribution"
    Environment = "Production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  
}


//changing image path in webserver
resource "null_resource" "null_res_4"  {
  depends_on = [
    aws_cloudfront_distribution.sd_cf
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.private_key.private_key_pem
    host     = aws_instance.instance_sd.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum -y install sed",
      "cd /var/www/html/",
      "sudo sed -i 's#terraform-and-aws.png#https://${aws_cloudfront_distribution.sd_cf.domain_name}/image1.png#g' index.html",
      "sudo sed -i 's#shardul.jpeg#https://${aws_cloudfront_distribution.sd_cf.domain_name}/image2.jpeg#g' index.html"
    ]
  }
}

resource "null_resource" "null_res_2"{
depends_on = [
    null_resource.null_res_4
  ]
	provisioner "local-exec" {
		command= "echo ${aws_instance.instance_sd.public_ip} > public_ip.txt"
	}
	
}

resource "null_resource" "null_res_3"{
depends_on = [
    null_resource.null_res_2
  ]
provisioner "local-exec" {
		command= "start chrome ${aws_instance.instance_sd.public_ip}"
	}	
	
}	
	
		