variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "location" {
  type = string
}
variable "tags" {
  type = map(string)
}
variable "network" {
  type = map(string)
}
variable "ssh_public_key" {
  type = string
}
variable "vm_size" {
  type = string
}
variable "instances" {
  type = number
}
variable "database_endpoint" {
  type = string
}

variable "front_door_id" { type = string }
