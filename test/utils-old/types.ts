export type Address = {
    value: string
}

export type ContractId = {
    value: string
}

export type Account = {
    value: string
    is_contract: boolean
}

export type ContractAccount = {
    value: string
    is_contract: true
}

export type AddressAccount = {
    value: string
    is_contract: false
}

export type Identity = {
    ContractId?: { value: string }
    Address?: { value: string }
}

export type ContractIdentity = {
    ContractId?: { value: string }
}

export type AddressIdentity = {
    Address?: { value: string }
}
