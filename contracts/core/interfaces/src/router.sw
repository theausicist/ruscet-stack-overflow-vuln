// SPDX-License-Identifier: Apache-2.0
library;

use helpers::{context::*};

abi Router {
   #[storage(read, write)]
    fn initialize(
        vault: ContractId,
        usdg: ContractId,
        gov: Address
    );

    /*
          ____     _       _           _       
         / / /    / \   __| |_ __ ___ (_)_ __  
        / / /    / _ \ / _` | '_ ` _ \| | '_ \ 
       / / /    / ___ \ (_| | | | | | | | | | |
      /_/_/    /_/   \_\__,_|_| |_| |_|_|_| |_|                         
    */
    #[storage(write)]
    fn set_gov(gov: Address);

    #[storage(write)]
    fn update_plugin(plugin: ContractId, is_active: bool);

    #[storage(write)]
    fn update_approved_plugins(plugin: ContractId, is_approved: bool);

    /*
          ____  ____        _     _ _      
         / / / |  _ \ _   _| |__ | (_) ___ 
        / / /  | |_) | | | | '_ \| | |/ __|
       / / /   |  __/| |_| | |_) | | | (__ 
      /_/_/    |_|    \__,_|_.__/|_|_|\___|
    */
    #[payable]
    #[storage(read)]
    fn plugin_transfer(
        asset: AssetId,
        account: Address,
        receiver: Account,
        amount: u64 
    );

    #[storage(read)]
    fn plugin_increase_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        size_delta: u256,
        is_long: bool 
    );

    #[storage(read)]
    fn plugin_decrease_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        collateral_delta: u256,
        size_delta: u256,
        is_long: bool,
        receiver: Account
    ) -> u256;

    #[payable]
    #[storage(read)]
    fn direct_pool_deposit(asset: AssetId);
}