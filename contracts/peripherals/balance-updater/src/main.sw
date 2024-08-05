// SPDX-License-Identifier: Apache-2.0
contract;

/*
 ____        _                        _   _           _       _            
| __ )  __ _| | __ _ _ __   ___ ___  | | | |_ __   __| | __ _| |_ ___ _ __ 
|  _ \ / _` | |/ _` | '_ \ / __/ _ \ | | | | '_ \ / _` |/ _` | __/ _ \ '__|
| |_) | (_| | | (_| | | | | (_|  __/ | |_| | |_) | (_| | (_| | ||  __/ |   
|____/ \__,_|_|\__,_|_| |_|\___\___|  \___/| .__/ \__,_|\__,_|\__\___|_|   
                                           |_|
*/


use std::{
    auth::msg_sender,
    block::timestamp,
    call_frames::{
        contract_id,
        msg_asset_id,
    },
    constants::BASE_ASSET_ID,
    context::*,
    revert::require,
    asset::{
        force_transfer_to_contract,
        mint_to_address,
        transfer_to_address,
    },
    primitive_conversions::u64::*
};
use std::hash::*;
use peripheral_interfaces::balance_updater::BalanceUpdater;
use core_interfaces::{
    vault::Vault,
    vault_storage::VaultStorage
};
use interfaces::wrapped_asset::{
    WrappedAsset as WrappedAssetABI
};
use helpers::{
    context::*, 
    utils::*,
    transfer::*,
    asset::*
};

enum Error {
    BalanceUpdaterInvalidAssetForwarded: (),
    BalanceUpdaterInsufficientAmountForwarded: ()
}

impl BalanceUpdater for Contract {
    #[payable]
    fn update_balance(
        vault_: ContractId,
        asset: AssetId,
        usdg: WrappedAsset,
        usdg_amount: u64
    ) {
        require(
            msg_asset_id() == asset,
            Error::BalanceUpdaterInvalidAssetForwarded
        );

        let vault = abi(Vault, vault_.value);
        let vault_storage = abi(VaultStorage, vault.get_vault_storage().value);

        // @TODO: potential revert here
        let pool_amount = u64::try_from(vault_storage.get_pool_amounts(asset)).unwrap();
        // @TODO: potential revert here
        let fee = u64::try_from(vault_storage.get_fee_reserves(asset)).unwrap();
        let balance = balance_of(vault_, asset);

        let transfer_amount = pool_amount + fee - balance;
        require(
            msg_amount() >= transfer_amount,
            Error::BalanceUpdaterInsufficientAmountForwarded
        );

        transfer_assets(
            asset,
            Account::from(vault_),
            transfer_amount
        );

        _unwrap(usdg, usdg_amount);

        // forward assets to vault
        transfer_assets(
            usdg,
            Account::from(vault_),
            usdg_amount
        );

        let _ = vault.sell_usdg(asset, get_sender());
    }
}

fn _unwrap(
    asset: WrappedAsset,
    amount: u64,
) {
    let asset_to_unwrap = abi(WrappedAssetABI, asset.value);

    // transfer wrapped asset to self
    asset_to_unwrap.transfer_on_behalf_of(
        get_sender(),
        Account::from(contract_id()),
        amount
    );

    // unwrap amount
    asset_to_unwrap.withdraw(amount);
}