import { getAssetId as getAssetIdFuels } from "fuels"
import { FungibleAbi } from "../../types"
import { Account } from "./types"

export function toAsset(value: any) {
    return { value: getAssetId(value) }
}

export function getAssetId(
    fungibleContract: any,
    sub_id: string = "0x0000000000000000000000000000000000000000000000000000000000000000",
): string {
    return getAssetIdFuels(fungibleContract.id.toHexString(), sub_id)
}

export async function transfer(fungibleContract: FungibleAbi, to: Account, amount: number | string) {
    const call = fungibleContract.functions
        .transfer(to, amount)
        .callParams({
            forward: [amount, getAssetId(fungibleContract)],
            // gasLimit: 1000000,
        })
        .txParams({
            gasLimit: 1000000,
        })

    await call.call()
}
