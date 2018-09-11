# Terraform AWS VPC

## Module inputs

| Name                | Description                                                                              |  Type  | Default | Required |
|:--------------------|:-----------------------------------------------------------------------------------------|:------:|:-------:|:--------:|
| azs                 | VPC AZs                                                                                  |  list  |    -    |   yes    |
| cidr                | VPC Cidr Block                                                                           | string |    -    |   yes    |
| name                | VPC Name                                                                                 | string |    -    |   yes    |
| public_key          | EC2 Public key used to provision servers                                                 | string |    -    |   yes    |
| tags                | Default set of tags to apply to VPC resources                                            |  map   | `<map>` |    no    |
| enable_bastion_host | If true, A bastion / jump host will be started in a public subnet                        | string | `true`  |    no    |
| enable_managed_nat  | If true, Managed NAT Gateways will be used, otherwise EC2 NAT instances will be spawn up | string | `false` |    no    |


## Module usage example

```hcl

```

*Based on [standard module structure](https://www.terraform.io/docs/modules/create.html#standard-module-structure) guidelines*
