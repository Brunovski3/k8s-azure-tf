variable "location" {
  description = "Região Azure"
  type        = string
  default     = "Brazil South"
}

variable "resource_group_name" {
  description = "Nome base do resource group (ganha sufixo único de 4 hex chars)"
  type        = string
  default     = "rg-k8s-course"
}

variable "cluster_name" {
  description = "Nome do cluster. Usado como prefixo de todos os nomes de recursos de rede e VMs"
  type        = string
  default     = "k8s"
}

variable "vm_count" {
  description = "Quantidade de VMs (1 control-plane + N-1 workers)"
  type        = number
  default     = 3
}

variable "vm_size" {
  description = "SKU da VM. B2s é o mínimo viável pro control-plane do k8s"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Usuário admin da VM"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Caminho da sua chave pública SSH"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "my_ip" {
  description = "Seu IP público (pra liberar SSH só pra você). Ex: 200.1.2.3/32"
  type        = string
}

variable "shutdown_time" {
  description = "Horário do auto-shutdown diário, formato HHmm"
  type        = string
  default     = "2300"
}

variable "shutdown_timezone" {
  description = "Timezone do auto-shutdown"
  type        = string
  default     = "E. South America Standard Time"
}

variable "worker_vm_size" {
  description = "SKU dos workers. 1 vCPU pra caber na cota de 4  que eu tenho por conta de ser estudante ;-;"
  type        = string
  default     = "Standard_B1ms"
}
