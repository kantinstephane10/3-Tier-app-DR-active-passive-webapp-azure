variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "origins" {
  type = map(object({ hostname = string, priority = number }))
}
variable "tags" {
  type = map(string)
}
