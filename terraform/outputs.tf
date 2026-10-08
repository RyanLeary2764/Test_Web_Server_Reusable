output "preview_url" {
  value = "http://${aws_instance.preview.public_ip}"
}
output "instance_id" {
  value = aws_instance.preview.id
}
output "ansible_inventory" {
  value = {
    all = {
      hosts = {
        preview = {
          ansible_host               = aws_instance.preview.public_ip
          ansible_user               = "ubuntu"
          ansible_python_interpreter = "/usr/bin/python3"
        }
      }
    }
  }
}
