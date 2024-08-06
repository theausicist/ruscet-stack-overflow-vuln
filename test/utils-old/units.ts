import { BigNumber } from "ethers"
import BN from "bn.js"
import { BN as BNFuels } from "fuels"

// 18446744073709551615 // max(u64)
// 340282366920938463463374607431768211455 // max(u128)
// 115792089237316195423570985008687907853269984665640564039457584007913129639935 // max(u256)

export function toUsd(value: any): string {
    const normalizedValue = parseInt((value * Math.pow(10, 10)) as any)
    return BigNumber.from(normalizedValue).mul(BigNumber.from(10).pow(20)).toString()
}

export function toUsdBN(value: any) {
    const normalizedValue = parseInt((value * Math.pow(10, 10)) as any)
    return BigNumber.from(normalizedValue).mul(BigNumber.from(10).pow(20))
}

export function toNormalizedPrice(value: number): string {
    return toUsd(value)
}

export function toPrice(value: number): string {
    // console.log("[toPrice] Value:", parseInt((value * Math.pow(10, 8)) as any).toString())
    return parseInt((value * Math.pow(10, 8)) as any).toString()
}

export function expandDecimals(num: string | number, decimals: number = 8): string {
    return BigNumber.from(num).mul(BigNumber.from(10).pow(decimals)).toString()
}

export function asStr(num: number) {
    return num.toString()
}
