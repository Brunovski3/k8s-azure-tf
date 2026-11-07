# k8s-azure-tf

Blueprint Terraform para subir um cluster Kubernetes com kubeadm na Azure: 3 VMs Ubuntu (1 control-plane + 2 workers), VNet isolada, NSG restrito e auto-shutdown diário para não queimar crédito.

## Arquitetura

```text
Resource Group (sufixo único por apply)
├─ VNet 10.10.0.0/16
│  └─ Subnet 10.10.1.0/24
│     └─ 3x VM Ubuntu 22.04 (k8s-master, k8s-worker-1, k8s-worker-2)
│        └─ cloud-init: pré-requisitos do kubeadm
└─ NSG
   ├─ SSH (22)        ← só seu IP
   ├─ K8s API (6443)  ← só seu IP
   ├─ NodePort range  ← só seu IP
   └─ Interno         ← livre dentro da subnet (etcd, kubelet, CNI)
```

Tudo é identificado por nome (fórmula: `cluster_name` + sufixo de 4 hex por apply), então é possível subir o mesmo projeto duas vezes sem conflito; basta mudar `resource_group_name` ou `cluster_name` se for manter ambos.

## Uso

```bash
cp terraform.tfvars.example terraform.tfvars
# edite terraform.tfvars com seu IP público (curl ifconfig.me) e caminho da chave SSH
az login
terraform init
terraform plan
terraform apply
```

Ao final, os outputs `vm_public_ips` e `ssh_commands` mostram IP público e o comando `ssh` pronto de cada VM.

Depois do apply, o kubeadm é manual (proposital, é o que o curso propõe):

```bash
# no master
ssh ubuntu@<ip-master>
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
# copie o comando kubeadm join <...> que ele imprimiu

# em cada worker
ssh ubuntu@<ip-worker>
sudo <comando do join>
```

## Auto-shutdown (FinOps)

As VMs desligam sozinhas todo dia às 23h (horário de Brasília). Isso só *dealloca* a VM, o disco continua cobrado a valores menores; pra voltar, use `az vm start` ou o Portal.

## Tags (FinOps)

Todos os recursos saem com `managed_by=terraform` e `project=k8s-azure-tf`. Use var.tags para adicionar o seu (ex: cost-center, ambiente, dono), se a conta precisa.

## Estado

O state roda local, é um lab. Se quiser compartilhar com equipe, deixe um backend apontando pra storage account:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "<sua sa>"
    container_name       = "tfstate"
    key                  = "k8s-azure-tf.tfstate"
  }
}
```

## Variáveis principais

| Variável | Default | O que faz |
|---|---|---|
| `cluster_name` | `k8s` | Prefixo de todos os nomes de recurso |
| `vm_count` | `3` | 1 control-plane + N-1 workers |
| `vm_size` | `Standard_B2s` | SKU do control-plane |
| `worker_vm_size` | `Standard_B1ms` | SKU dos workers (1 vCPU, cabe na cota de estudante) |
| `my_ip` | — | Seu IP público, pra SSH/API só pra você |
| `shutdown_time` | `2300` | Horário do auto-shutdown diário |
| `tags` | `{}` | Tags extras em todos os recursos |

## Licença

MIT. Use, copie, adapte.
