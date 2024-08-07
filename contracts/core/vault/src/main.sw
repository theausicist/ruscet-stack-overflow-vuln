// SPDX-License-Identifier: Apache-2.0
contract;

mod events;
mod constants;
mod utils;
mod errors;

/*
__     __          _ _   
\ \   / /_ _ _   _| | |_ 
 \ \ / / _` | | | | | __|
  \ V / (_| | |_| | | |_ 
   \_/ \__,_|\__,_|_|\__|
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
    storage::storage_vec::*,
    asset::{
        force_transfer_to_contract,
        mint_to_address,
        transfer_to_address,
    },
    math::*,
    primitive_conversions::{
        u8::*,
        u64::*,
    }
};
use std::hash::*;
use helpers::{
    context::*, 
    utils::*,
    transfer::transfer_assets,
    signed_256::*,
    zero::*
};
use core_interfaces::{
    vault::Vault,
    vault_storage::{
        VaultStorage,
        Position,
        PositionKey,
    },
    vault_pricefeed::VaultPricefeed,
};
use asset_interfaces::usdg::USDG;
use events::*;
use constants::*;
use errors::*;
use utils::{
    update_cumulative_funding_rate as utils_update_cumulative_funding_rate,
    validate_decrease_position as utils_validate_decrease_position,
    validate_increase_position as utils_validate_increase_position,
};

storage {
    // gov is not restricted to an `Address` (EOA) or a `Contract` (external)
    // because this can be either a regular EOA (Address) or a Multisig (Contract)
    gov: Account = ZERO_ACCOUNT,

    // Vault storage contract
    storj: ContractId = ZERO_CONTRACT,

    is_initialized: bool = false
}

impl Vault for Contract {
    #[storage(read, write)]
    fn initialize(
        gov: Account,
        storj: ContractId,
    ) {
        require(!storage.is_initialized.read(), Error::VaultAlreadyInitialized);
        storage.is_initialized.write(true);

        storage.gov.write(gov);
        storage.storj.write(storj);
    }

    /*
          ____     _       _           _       
         / / /    / \   __| |_ __ ___ (_)_ __  
        / / /    / _ \ / _` | '_ ` _ \| | '_ \ 
       / / /    / ___ \ (_| | | | | | | | | | |
      /_/_/    /_/   \_\__,_|_| |_| |_|_|_| |_|                         
    */
    #[storage(read, write)]
    fn withdraw_fees(asset: AssetId, receiver: Account) -> u64 {
        _only_gov();

        let storj = abi(VaultStorage, storage.storj.read().into());

        // @TODO: potential revert here
        let amount = u64::try_from(storj.get_fee_reserves(asset)).unwrap();
        if amount == 0 {
            return 0;
        }

        storj.write_fee_reserves(asset, 0);
        _transfer_out(asset, amount, receiver);

        amount
    }

    /*
          ____ __     ___               
         / / / \ \   / (_) _____      __
        / / /   \ \ / /| |/ _ \ \ /\ / /
       / / /     \ V / | |  __/\ V  V / 
      /_/_/       \_/  |_|\___| \_/\_/  
    */
    #[storage(read)]
    fn get_vault_storage() -> ContractId {
        storage.storj.read()
    }

    #[storage(read)]
    fn get_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> (
        u256, u256, u256,
        u256, u256, Signed256,
        bool, u64,
        Position
    ) {
        let position_key = _get_position_key(
            account, 
            collateral_asset, 
            index_asset, 
            is_long
        );

        let storj = abi(VaultStorage, storage.storj.read().into());

        let position = storj.get_position(position_key);
        (
            position.size, // 0
            position.collateral, // 1
            position.average_price, // 2
            position.entry_funding_rate, // 3
            position.reserve_amount, // 4
            position.realized_pnl, // 5
            // position.realized_pnl >= 0, // 6
            !position.realized_pnl.is_neg, // 6
            position.last_increased_time, // 7
            position
        )
    }

    fn get_position_key(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> b256 {
        _get_position_key(
            account,
            collateral_asset,
            index_asset,
            is_long
        )
    }

    #[storage(read)]
    fn get_position_delta(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> (bool, u256) {
        _get_position_delta(
            account,
            collateral_asset,
            index_asset,
            is_long
        )
    }

    #[storage(read)]
    fn get_delta(
        index_asset: AssetId,
        size: u256,
        average_price: u256,
        is_long: bool,
        last_increased_time: u64,
    ) -> (bool, u256) {
        _get_delta(
            index_asset,
            size,
            average_price,
            is_long,
            last_increased_time
        )
    }

    #[storage(read)]
    fn get_entry_funding_rate(
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> u256 {
        _get_entry_funding_rate(
            collateral_asset,
            index_asset,
            is_long
        )
    }

    #[storage(read)]
    fn get_funding_fee(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        size: u256,
        entry_funding_rate: u256,
    ) -> u256 {
        _get_funding_fee(
            account,
            collateral_asset,
            index_asset,
            is_long,
            size,
            entry_funding_rate
        )
    }

    #[storage(read)]
    fn get_position_fee(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        size_delta: u256,
    ) -> u256 {
        _get_position_fee(
            account,
            collateral_asset,
            index_asset,
            is_long,
            size_delta
        )
    }

    // #[storage(read)]
    // fn get_max_price(asset: AssetId) -> u256 {
    //     _get_max_price(asset)
    // }

    // #[storage(read)]
    // fn get_min_price(asset: AssetId) -> u256 {
    //     _get_min_price(asset)
    // }

    // #[storage(read)]
    // fn asset_to_usd_min(asset: AssetId, asset_amount: u256) -> u256 {
    //     _asset_to_usd_min(asset, asset_amount)
    // }

    // #[storage(read)]
    // fn usd_to_asset_max(asset: AssetId, usd_amount: u256) -> u256 {
    //     _usd_to_asset_max(asset, usd_amount)
    // }

    // #[storage(read)]
    // fn usd_to_asset_min(asset: AssetId, usd_amount: u256) -> u256 {
    //     _usd_to_asset_min(asset, usd_amount)
    // }

    // #[storage(read)]
    // fn usd_to_asset(asset: AssetId, usd_amount: u256, price: u256) -> u256 {
    //     _usd_to_asset(asset, usd_amount, price)
    // }

    // #[storage(read)]
    // fn get_redemption_amount(
    //     asset: AssetId, 
    //     usdg_amount: u256
    // ) -> u256 {
    //     _get_redemption_amount(asset, usdg_amount)
    // }

    // #[storage(read)]
    // fn get_redemption_collateral(asset: AssetId) -> u256 {
    //     _get_redemption_collateral(asset)
    // }

    // #[storage(read)]
    // fn get_redemption_collateral_usd(asset: AssetId) -> u256 {
    //     _asset_to_usd_min(
    //         asset,
    //         _get_redemption_collateral(asset)
    //     )
    // }

    #[storage(read)]
    fn get_position_leverage(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
    ) -> u256 {
        let position_key = _get_position_key(
            account, 
            collateral_asset, 
            index_asset, 
            is_long
        );
        let storj = abi(VaultStorage, storage.storj.read().into());

        let position = storj.get_position(position_key);
        require(
            position.collateral > 0,
            Error::VaultInvalidPosition
        );

        position.size * BASIS_POINTS_DIVISOR.as_u256() / position.collateral
    }

    #[storage(read)]
    fn get_fee_basis_points(
        asset: AssetId,
        usdg_delta: u256,
        fee_basis_points: u256,
        tax_basis_points: u256,
        increment: bool
    ) -> u256 {
        _get_fee_basis_points(
            asset,
            usdg_delta,
            fee_basis_points,
            tax_basis_points,
            increment,
        )
    }

    #[storage(read)]
    fn get_target_usdg_amount(asset: AssetId) -> u256 {
        _get_target_usdg_amount(asset)
    }

    #[storage(read)]
    fn get_utilization(asset: AssetId) -> u256 {
        let storj = abi(VaultStorage, storage.storj.read().into());

        let pool_amount = storj.get_pool_amounts(asset);
        if pool_amount == 0 {
            return 0;
        }

        let reserved_amount = storj.get_reserved_amounts(asset);
        
        reserved_amount * FUNDING_RATE_PRECISION / pool_amount
    }

    #[storage(read)]
    fn get_global_short_delta(asset: AssetId) -> (bool, u256) {
        _get_global_short_delta(asset)
    }

    #[storage(read)]
    fn validate_liquidation(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        should_raise: bool,
    ) -> (u256, u256) {
        _validate_liquidation(
            account,
            collateral_asset,
            index_asset,
            is_long,
            should_raise
        )
    }

    /*
          ____  ____        _     _ _      
         / / / |  _ \ _   _| |__ | (_) ___ 
        / / /  | |_) | | | | '_ \| | |/ __|
       / / /   |  __/| |_| | |_) | | | (__ 
      /_/_/    |_|    \__,_|_.__/|_|_|\___|
    */
    #[storage(read, write)]
    fn update_cumulative_funding_rate(collateral_asset: AssetId, index_asset: AssetId) {
        // _update_cumulative_funding_rate(collateral_asset, index_asset);
    }

    #[payable]
    #[storage(read, write)]
    fn direct_pool_deposit(asset: AssetId) {
        // // deposit into the pool without minting USDG tokens
        // // useful in allowing the pool to become over-collaterised
        // let storj = abi(VaultStorage, storage.storj.read().into());
        
        // require(
        //     storj.is_asset_whitelisted(asset),
        //     Error::VaultAssetNotWhitelisted
        // );

        // let amount = _transfer_in(asset).as_u256();
        // // @TODO: check this
        // require(amount > 0, Error::VaultInvalidAssetAmount);
        // _increase_pool_amount(asset, amount);

        // log(DirectPoolDeposit {
        //     asset: asset,
        //     amount: amount,
        // });
    }

    #[storage(read, write)]
    fn buy_usdg(asset: AssetId, receiver: Account) -> u256 {
        _validate_manager();

        let storj = abi(VaultStorage, storage.storj.read().into());

        require(
            storj.is_asset_whitelisted(asset),
            Error::VaultAssetNotWhitelisted
        );

        storj.write_use_swap_pricing(true);

        let asset_amount = _transfer_in(asset);
        require(asset_amount > 0, Error::VaultInvalidAssetAmount);

        _update_cumulative_funding_rate(asset, asset);

        let price = _get_min_price(asset);
        let usdg = storj.get_usdg();

        let mut usdg_amount = asset_amount.as_u256() * price / PRICE_PRECISION;
        usdg_amount = _adjust_for_decimals(usdg_amount, asset, usdg);
        require(usdg_amount > 0, Error::VaultInvalidUsdgAmount);

        let fee_basis_points = _get_buy_usdg_fee_basis_points(
            asset,
            usdg_amount
        );

        let amount_after_fees = 
            _collect_swap_fees(asset, asset_amount, u64::try_from(fee_basis_points).unwrap()).as_u256();

        let mut mint_amount = amount_after_fees * price / PRICE_PRECISION;
        mint_amount = _adjust_for_decimals(mint_amount, asset, usdg);

        _increase_usdg_amount(asset, mint_amount);
        _increase_pool_amount(asset, amount_after_fees);

        // require usdg_amount to be less than u64::max
        require(
            mint_amount < u64::max().as_u256(),
            Error::VaultInvalidMintAmountGtU64Max
        );

        let usdg = abi(USDG, storj.get_usdg_contr().into());
        usdg.mint(
            receiver,
            u64::try_from(mint_amount).unwrap()
        );

        // log(BuyUSDG {
        //     account: Address::from(receiver.into()),
        //     asset,
        //     asset_amount,
        //     usdg_amount: mint_amount,
        //     fee_basis_points,
        // });

        storj.write_use_swap_pricing(false);

        mint_amount
    }

    #[storage(read, write)]
    fn sell_usdg(asset: AssetId, receiver: Account) -> u256 {
        _validate_manager();
        
        let storj = abi(VaultStorage, storage.storj.read().into());
        
        require(
            storj.is_asset_whitelisted(asset),
            Error::VaultAssetNotWhitelisted
        );

        storj.write_use_swap_pricing(true);

        let usdg = storj.get_usdg();

        let usdg_amount = _transfer_in(usdg).as_u256();
        require(usdg_amount > 0, Error::VaultInvalidUsdgAmount);

        _update_cumulative_funding_rate(asset, asset);

        let redemption_amount = _get_redemption_amount(asset, usdg_amount);
        require(redemption_amount > 0, Error::VaultInvalidRedemptionAmount);

        _decrease_usdg_amount(asset, usdg_amount);
        _decrease_pool_amount(asset, redemption_amount);

        // require usdg_amount to be less than u64::max
        require(
            usdg_amount < u64::max().as_u256(),
            Error::VaultInvalidUSDGBurnAmountGtU64Max
        );

        let _amount = u64::try_from(usdg_amount).unwrap();

        abi(USDG, storj.get_usdg_contr().into()).burn{
            // @TODO: this is prob a buggy implementation of the USDG native asset? 
            asset_id: usdg.into(),
            coins: _amount
        }(
            Account::from(contract_id()),
            _amount
        );

        // the _transferIn call increased the value of tokenBalances[usdg]
        // usually decreases in token balances are synced by calling _transferOut
        // however, for UDFG, the assets are burnt, so _updateTokenBalance should
        // be manually called to record the decrease in assets
        _update_asset_balance(usdg);

        let fee_basis_points = _get_sell_usdg_fee_basis_points(
            asset,
            usdg_amount,
        );
        let amount_out = _collect_swap_fees(
            asset, 
            u64::try_from(redemption_amount).unwrap(), 
            u64::try_from(fee_basis_points).unwrap(), 
        );
        require(amount_out > 0, Error::VaultInvalidAmountOut);

        _transfer_out(asset, amount_out, receiver);

        // log(SellUSDG {
        //     account: Address::from(receiver.into()),
        //     asset,
        //     usdg_amount,
        //     asset_amount: amount_out,
        //     fee_basis_points,
        // });

        storj.write_use_swap_pricing(false);

        amount_out.as_u256()
    }

    #[payable]
    #[storage(read, write)]
    fn swap(
        asset_in: AssetId,
        asset_out: AssetId,
        receiver: Account
    ) -> u64 {
        let storj = abi(VaultStorage, storage.storj.read().into());

        require(
            storj.is_swap_enabled(),
            Error::VaultSwapsNotEnabled
        );
        require(
            storj.is_asset_whitelisted(asset_in),
            Error::VaultAssetInNotWhitelisted
        );
        require(
            storj.is_asset_whitelisted(asset_out),
            Error::VaultAssetOutNotWhitelisted
        );
        require(asset_in != asset_out, Error::VaultAssetsAreEqual);

        storj.write_use_swap_pricing(true);

        _update_cumulative_funding_rate(asset_in, asset_in);
        _update_cumulative_funding_rate(asset_out, asset_out);

        let amount_in = _transfer_in(asset_in).as_u256();
        require(amount_in > 0, Error::VaultInvalidAmountIn);

        let price_in = _get_min_price(asset_in);
        let price_out = _get_max_price(asset_out);

        let mut amount_out = amount_in * price_in / price_out;
        amount_out = _adjust_for_decimals(amount_out, asset_in, asset_out);

        // adjust usdgAmounts by the same usdgAmount as debt is shifted between the assets
        let mut usdg_amount = amount_in * price_in / PRICE_PRECISION;
        usdg_amount = _adjust_for_decimals(usdg_amount, asset_in, storj.get_usdg());

        let fee_basis_points = _get_swap_fee_basis_points(
            asset_in, 
            asset_out, 
            usdg_amount,
        );

        let amount_out_after_fees = _collect_swap_fees(
            asset_out, 
            u64::try_from(amount_out).unwrap(),
            u64::try_from(fee_basis_points).unwrap()
        );

        _increase_usdg_amount(asset_in, usdg_amount);
        _decrease_usdg_amount(asset_out, usdg_amount);

        _increase_pool_amount(asset_in, amount_in);
        _decrease_pool_amount(asset_out, amount_out);

        _validate_buffer_amount(asset_out);

        _transfer_out(asset_out, amount_out_after_fees, receiver);

        // log(Swap {
        //     account: Address::from(receiver.into()),
        //     asset_in,
        //     asset_out,
        //     amount_in,
        //     amount_out,
        //     amount_out_after_fees: amount_out_after_fees.as_u256(),
        //     fee_basis_points,
        // });

        storj.write_use_swap_pricing(false);

        amount_out_after_fees
    }

    #[payable]
    #[storage(read, write)]
    fn increase_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        size_delta: u256,
        is_long: bool,
    ) {
        let storj = abi(VaultStorage, storage.storj.read().into());

        require(
            storj.is_leverage_enabled(),
            Error::VaultLeverageNotEnabled
        );
        _validate_router(Account::from(account));
        _validate_assets(collateral_asset, index_asset, is_long);

        utils_validate_increase_position(
            account,
            collateral_asset,
            index_asset,
            size_delta,
            is_long 
        );

        _update_cumulative_funding_rate(collateral_asset, index_asset);

        let position_key = _get_position_key(
            account, 
            collateral_asset, 
            index_asset, 
            is_long
        );

        let mut position = storj.get_position(position_key);

        let price = if is_long {
            _get_max_price(index_asset)
        } else {
            _get_min_price(index_asset)
        };

        if position.size == 0 {
            position.average_price = price;
        }

        if position.size > 0 && size_delta > 0 {
            position.average_price = _get_next_average_price(
                index_asset,
                position.size,
                position.average_price,
                is_long,
                price,
                size_delta,
                position.last_increased_time
            );
        }

        let fee = _collect_margin_fees(
            account,
            collateral_asset,
            index_asset,
            is_long,
            size_delta,
            position.size,
            position.entry_funding_rate,
        );

        let collateral_delta = _transfer_in(collateral_asset).as_u256();
        let collateral_delta_usd = _asset_to_usd_min(collateral_asset, collateral_delta);

        position.collateral = position.collateral + collateral_delta_usd;

        require(
            position.collateral >= fee,
            Error::VaultInsufficientCollateralForFees
        );
        position.collateral = position.collateral - fee;
        position.entry_funding_rate = _get_entry_funding_rate(
            collateral_asset,
            index_asset,
            is_long
        );
        position.size = position.size + size_delta;
        position.last_increased_time = timestamp();

        require(
            position.size > 0,
            Error::VaultInvalidPositionSize
        );

        _validate_position(position.size, position.collateral);
        // we need to have a storage write here because _validate_liquidation constructs the position key and 
        // validates the average_price. If not for this position write, it would receive a stale avg price (could be 0)
        storj.write_position(position_key, position);
        _validate_liquidation(
            account,
            collateral_asset,
            index_asset,
            is_long,
            true 
        );

        // scrop variables to prevent stack overflow errors (which aren't detected at compile-time)
        {
            // reserve assets to pay profits on the position
            let reserve_delta = _usd_to_asset_max(collateral_asset, size_delta);
            position.reserve_amount = position.reserve_amount + reserve_delta;
            _increase_reserved_amount(collateral_asset, reserve_delta);
        }

        if is_long {
            // guaranteed_usd stores the sum of (position.size - position.collateral) for all positions
            // if a fee is charged on the collateral then guaranteed_usd should be increased by that 
            // fee amount since (position.size - position.collateral) would have increased by `fee`
            _increase_guaranteed_usd(collateral_asset, size_delta + fee);
            _decrease_guaranteed_usd(collateral_asset, collateral_delta_usd);

            // treat the deposited collateral as part of the pool
            _increase_pool_amount(collateral_asset, collateral_delta);

            // fees need to be deducted from the pool since fees are deducted from position.collateral
            // and collateral is treated as part of the pool
            _decrease_pool_amount(collateral_asset, _usd_to_asset_min(collateral_asset, fee));
        } else {
            let global_short_size = storj.get_global_short_sizes(index_asset);
            if global_short_size == 0 {
                storj.write_global_short_average_prices(index_asset, price);
            } else {
                let new_price = _get_next_global_short_average_price(
                    index_asset,
                    price,
                    size_delta
                );

                storj.write_global_short_average_prices(index_asset, new_price);
            }

            _increase_global_short_size(index_asset, size_delta);
        }
 
        // log(IncreasePosition {
        //     key: position_key,
        //     account,
        //     collateral_asset,
        //     index_asset,
        //     collateral_delta: collateral_delta_usd,
        //     size_delta,
        //     is_long,
        //     price,
        //     fee,
        // });

        // log(UpdatePosition {
        //     key: position_key,
        //     size: position.size,
        //     collateral: position.collateral,
        //     average_price: position.average_price,
        //     entry_funding_rate: position.entry_funding_rate,
        //     reserve_amount: position.reserve_amount,
        //     realized_pnl: position.realized_pnl,
        //     mark_price: price,
        // });

        storj.write_position(position_key, position);
    }

    #[storage(read, write)]
    fn decrease_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        collateral_delta: u256,
        size_delta: u256,
        is_long: bool,
        receiver: Account
    ) -> u256 {
        _validate_router(Account::from(account));
        _decrease_position(
            account,
            collateral_asset,
            index_asset,
            collateral_delta,
            size_delta,
            is_long,
            receiver
        )
    }

    #[storage(read, write)]
    fn liquidate_position(
        account: Address,
        collateral_asset: AssetId,
        index_asset: AssetId,
        is_long: bool,
        fee_receiver: Account
    ) {
        let storj = abi(VaultStorage, storage.storj.read().into());

        if storj.get_in_private_liquidation_mode() {
            require(
                storj.get_is_liquidator(get_sender()),
                Error::VaultInvalidLiquidator
            );
        }

        // set includeAmmPrice to false to prevent manipulated liquidations
        storj.write_include_amm_price(false);

        _update_cumulative_funding_rate(collateral_asset, index_asset);

        let position_key = _get_position_key(
            account, 
            collateral_asset, 
            index_asset, 
            is_long
        );

        let position = storj.get_position(position_key);
        require(position.size > 0, Error::VaultEmptyPosition);

        let liquidation_fee_usd = storj.get_liquidation_fee_usd();

        let (liquidation_state, margin_fees) = _validate_liquidation(
            account,
            collateral_asset,
            index_asset,
            is_long,
            false 
        );
        require(
            liquidation_state != 0,
            Error::VaultPositionCannotBeLiquidated
        );

        if liquidation_state == 2 {
            // max leverage exceeded but there is collateral remaining after deducting losses 
            // so decreasePosition instead
            _decrease_position(
                account,
                collateral_asset,
                index_asset,
                0,
                position.size,
                is_long,
                Account::from(account)
            );
            storj.write_include_amm_price(true);
            return;
        }

        let fee_assets = _usd_to_asset_min(collateral_asset, margin_fees);
        storj.write_fee_reserves(
            collateral_asset,
            storj.get_fee_reserves(collateral_asset) + fee_assets
        );
        // log(CollectMarginFees {
        //     asset: collateral_asset,
        //     fee_usd: margin_fees,
        //     fee_assets,
        // });

        _decrease_reserved_amount(collateral_asset, position.reserve_amount);

        if is_long {
            _decrease_guaranteed_usd(collateral_asset, position.size - position.collateral);
            _decrease_pool_amount(collateral_asset, _usd_to_asset_min(collateral_asset, margin_fees));
        }

        let mark_price = if is_long {
            _get_min_price(index_asset)
        } else {
            _get_max_price(index_asset)
        };

        // log(LiquidatePosition {
        //     key: position_key,
        //     account,
        //     collateral_asset,
        //     index_asset,
        //     is_long,
        //     size: position.size,
        //     collateral: position.collateral,
        //     reserve_amount: position.reserve_amount,
        //     realized_pnl: position.realized_pnl,
        //     mark_price,
        // });

        if !is_long && margin_fees < position.collateral {
            let remaining_collateral = position.collateral - margin_fees;
            _increase_pool_amount(collateral_asset, _usd_to_asset_min(collateral_asset, remaining_collateral));
        }

        if !is_long {
            _decrease_global_short_size(index_asset, position.size);
        }

        storj.write_position(position_key, Position::default());

        // pay the fee receiver using the pool, we assume that in general the liquidated amount should be sufficient to cover
        // the liquidation fees
        _decrease_pool_amount(collateral_asset, _usd_to_asset_min(collateral_asset, liquidation_fee_usd));
        _transfer_out(
            collateral_asset, 
            // @TODO: potential revert here
            u64::try_from(_usd_to_asset_min(collateral_asset, liquidation_fee_usd)).unwrap(),
            fee_receiver
        );

        storj.write_include_amm_price(true);
    }
}

/*
    ____  ___       _                        _ 
   / / / |_ _|_ __ | |_ ___ _ __ _ __   __ _| |
  / / /   | || '_ \| __/ _ \ '__| '_ \ / _` | |
 / / /    | || | | | ||  __/ |  | | | | (_| | |
/_/_/    |___|_| |_|\__\___|_|  |_| |_|\__,_|_|
*/

#[storage(read)]
fn _only_gov() {
    require(get_sender() == storage.gov.read(), Error::VaultForbiddenNotGov);
}

#[storage(read)]
fn _validate_manager() {
    let storj = abi(VaultStorage, storage.storj.read().into());

    if storj.get_in_manager_mode() {
        require(
            storj.get_is_manager(get_sender()),
            Error::VaultForbiddenNotManager
        );
    }
}

#[storage(read, write)]
fn _transfer_in(asset_id: AssetId) -> u64 {
    let storj = abi(VaultStorage, storage.storj.read().into());
    
    let prev_balance = storj.get_asset_balance(asset_id);
    let next_balance = balance_of(contract_id(), asset_id);
    storj.write_asset_balances(asset_id, next_balance);

    return next_balance - prev_balance;
}

#[storage(read, write)]
fn _transfer_out(asset_id: AssetId, amount: u64, receiver: Account) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    // Native asset docs: https://docs.fuel.network/docs/sway/blockchain-development/native_assets/
    transfer_assets(
        asset_id, 
        receiver,
        amount
    );
    storj.write_asset_balances(asset_id, balance_of(contract_id(), asset_id));
}

#[storage(read, write)]
fn _increase_usdg_amount(asset: AssetId, amount: u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let new_usdg_amount = storj.get_usdg_amount(asset) + amount;
    storj.write_usdg_amounts(asset, new_usdg_amount);

    let max_usdg_amount = storj.get_max_usdg_amount(asset);
    if max_usdg_amount != 0 {
        require(new_usdg_amount <= max_usdg_amount, Error::VaultMaxUsdgExceeded);
    }
    // log(IncreaseUsdgAmount {
    //     asset: asset,
    //     amount: amount,
    // });
}

#[storage(read, write)]
fn _decrease_usdg_amount(asset: AssetId, amount: u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let value = storj.get_usdg_amount(asset);
    // since USDG can be minted using multiple assets
    // it is possible for the USDG debt for a single asset to be less than zero
    // the USDG debt is capped to zero for this case
    if value <= amount {
        storj.write_usdg_amounts(asset, 0);
        // log(DecreaseUsdgAmount {
        //     asset: asset,
        //     amount: value,
        // });
    } else {
        storj.write_usdg_amounts(asset, value - amount);
        // log(DecreaseUsdgAmount {
        //     asset: asset,
        //     amount: amount,
        // });
    }
}

#[storage(read, write)]
fn _increase_pool_amount(asset: AssetId, amount: u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let new_pool_amount = storj.get_pool_amounts(asset) + amount;
    storj.write_pool_amounts(asset, new_pool_amount);

    let balance = balance_of(contract_id(), asset);

    require(new_pool_amount <= balance.as_u256(), Error::VaultInvalidIncrease);

    // log(IncreasePoolAmount {
    //     asset: asset,
    //     amount: amount,
    // });
}

#[storage(read, write)]
fn _decrease_pool_amount(asset: AssetId, amount: u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let pool_amount = storj.get_pool_amounts(asset);

    require(pool_amount >= amount, Error::VaultPoolAmountExceeded);

    let new_pool_amount = pool_amount - amount;

    storj.write_pool_amounts(asset, new_pool_amount);

    require(
        storj.get_reserved_amounts(asset) <= new_pool_amount,
        Error::VaultReserveExceedsPool
    );
}

#[storage(read, write)]
fn _increase_global_short_size(asset: AssetId, amount: u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());
    
    storj.write_global_short_sizes(
        asset,
        storj.get_global_short_sizes(asset) + amount
    );

    let max_size = storj.get_max_global_short_sizes(asset);
    if max_size != 0 {
        require(
            storj.get_global_short_sizes(asset) <= max_size,
            Error::VaultMaxShortsExceeded
        );
    }
}

#[storage(read, write)]
fn _decrease_global_short_size(asset: AssetId, amount: u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let global_short_size = storj.get_global_short_sizes(asset);

    if amount > global_short_size {
        storj.write_global_short_sizes(asset, 0);
        return;
    }

    storj.write_global_short_sizes(
        asset,
        global_short_size - amount
    );
}

#[storage(read, write)]
fn _increase_guaranteed_usd(asset: AssetId, usd_amount: u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    storj.write_guaranteed_usd(
        asset,
        storj.get_guaranteed_usd(asset) + usd_amount
    );

    // log(IncreaseGuaranteedAmount {
    //     asset: asset,
    //     amount: usd_amount,
    // });
}

#[storage(read, write)]
fn _decrease_guaranteed_usd(asset: AssetId, usd_amount: u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());
    
    storj.write_guaranteed_usd(
        asset,
        storj.get_guaranteed_usd(asset) - usd_amount
    );

    // log(DecreaseGuaranteedAmount {
    //     asset: asset,
    //     amount: usd_amount,
    // });
}

#[storage(read, write)]
fn _increase_reserved_amount(asset: AssetId, amount: u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    storj.write_reserved_amounts(
        asset,
        storj.get_reserved_amounts(asset) + amount
    );

    // log(__to_str_array("ERR: RESERVED AMOUNTS"));
    // log(storj.get_reserved_amounts(asset));
    // log(__to_str_array("ERR: POOL AMOUNTS"));
    // log(storj.get_pool_amounts(asset));
    // // @ERROR HERE: uncomment this block of code to reproduce error
    // require(
    //     storj.get_reserved_amounts(asset) <= storj.get_pool_amounts(asset),
    //     Error::VaultReserveExceedsPool
    // );

    // @SOLUTION HERE: comment this block of code to reproduce error
    {
        let reserved_amount = storj.get_reserved_amounts(asset);
        let pool_amount = storj.get_pool_amounts(asset);
        log(__to_str_array("SOL: RESERVED AMOUNTS"));
        log(reserved_amount);
        log(__to_str_array("SOL: POOL AMOUNTS"));
        log(pool_amount);
        require(
            reserved_amount <= pool_amount,
            Error::VaultReserveExceedsPool
        );
    }
    
    // log(IncreaseReservedAmount {
    //     asset: asset,
    //     amount: amount,
    // });
}

#[storage(read, write)]
fn _decrease_reserved_amount(asset: AssetId, amount: u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    if storj.get_reserved_amounts(asset) < amount {
        require(false, Error::VaultInsufficientReserve);
    }

    storj.write_reserved_amounts(
        asset,
        storj.get_reserved_amounts(asset) - amount
    );

    // log(DecreaseReservedAmount {
    //     asset: asset,
    //     amount: amount,
    // });
}

#[storage(read, write)]
fn _update_cumulative_funding_rate(collateral_asset: AssetId, index_asset: AssetId) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let should_update = utils_update_cumulative_funding_rate(collateral_asset, index_asset);
    if !should_update {
        return;
    }

    let last_funding_time = storj.get_last_funding_times(collateral_asset);
    let funding_interval = storj.get_funding_interval();

    if last_funding_time == 0 {
        storj.write_last_funding_times(
            collateral_asset, 
            timestamp() /* * funding_interval / funding_interval */
        );
        return;
    }

    if last_funding_time + funding_interval > timestamp() {
        return;
    }

    let funding_rate = _get_next_funding_rate(collateral_asset);
    storj.write_cumulative_funding_rates(
        collateral_asset, 
        storj.get_cumulative_funding_rates(collateral_asset) + funding_rate
    );
    storj.write_last_funding_times(collateral_asset, timestamp() /* * funding_interval / funding_interval */ );

    // log(UpdateFundingRate {
    //     asset: collateral_asset,
    //     funding_rate: storj.get_cumulative_funding_rates(collateral_asset)
    // });
}

#[storage(read)]
fn _get_next_funding_rate(asset: AssetId) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let last_funding_time = storj.get_last_funding_times(asset);
    let funding_interval = storj.get_funding_interval();

    if last_funding_time + funding_interval > timestamp() {
        return 0;
    }

    let intervals = timestamp() - last_funding_time / funding_interval;
    let pool_amount = storj.get_pool_amounts(asset);
    if pool_amount == 0 {
        return 0;
    }

    let funding_rate_factor = if storj.is_stable_asset(asset) {
        storj.get_stable_funding_rate_factor()
    } else {
        storj.get_funding_rate_factor()
    };

    return 
        funding_rate_factor.as_u256() * storj.get_reserved_amounts(asset)
        * intervals.as_u256() / pool_amount;
}

#[storage(read)]
fn _adjust_for_decimals(amount: u256, asset_div: AssetId, asset_mul: AssetId) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());
    
    let usdg = storj.get_usdg();
    let decimals_div = if asset_div == usdg {
        USDG_DECIMALS
    } else {
        storj.get_asset_decimals(asset_div)
    };

    let decimals_mul = if asset_mul == usdg {
        USDG_DECIMALS
    } else {
        storj.get_asset_decimals(asset_mul)
    };

    // @TODO: prob will need to switch to a bigger type like u128 or even u256 to handle
    // large arithmetic operations without overflow
    amount * 10.pow(decimals_mul.as_u32()).as_u256() / 10.pow(decimals_div.as_u32()).as_u256()
}

#[storage(read)]
fn _get_max_price(asset: AssetId) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let vault_pricefeed = abi(VaultPricefeed, storj.get_pricefeed_provider().into());
    vault_pricefeed.get_price(
        asset, 
        true,
        storj.get_include_amm_price(),
        storj.get_use_swap_pricing()
    )
}

#[storage(read)]
fn _get_min_price(asset: AssetId) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let vault_pricefeed = abi(VaultPricefeed, storj.get_pricefeed_provider().into());
    vault_pricefeed.get_price(
        asset, 
        false,
        storj.get_include_amm_price(),
        storj.get_use_swap_pricing()
    )
}

#[storage(read)]
fn _asset_to_usd_min(asset: AssetId, asset_amount: u256) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());
    
    if asset_amount == 0 {
        return 0;
    }

    let price = _get_min_price(asset);
    let decimals = storj.get_asset_decimals(asset);

    (asset_amount * price) / 10.pow(decimals.as_u32()).as_u256()
}

#[storage(read)]
fn _usd_to_asset_max(asset: AssetId, usd_amount: u256) -> u256 {
    if usd_amount == 0 {
        return 0;
    }

    // @notice this is CORRECT (asset_max -> get_min_price)
    let price = _get_min_price(asset);

    _usd_to_asset(asset, usd_amount, price)
}

#[storage(read)]
fn _usd_to_asset_min(asset: AssetId, usd_amount: u256) -> u256 {
    if usd_amount == 0 {
        return 0;
    }

    // @notice this is CORRECT (asset_min -> get_max_price)
    let price = _get_max_price(asset);

    _usd_to_asset(asset, usd_amount, price)
}

#[storage(read)]
fn _usd_to_asset(asset: AssetId, usd_amount: u256, price: u256) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    require(price != 0, Error::VaultPriceQueriedIsZero);

    if usd_amount == 0 {
        return 0;
    }

    let decimals = storj.get_asset_decimals(asset);

    (usd_amount * 10.pow(decimals.as_u32()).as_u256()) / price
}

#[storage(read)]
fn _get_target_usdg_amount(asset: AssetId) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let supply = abi(USDG, storj.get_usdg_contr().into()).total_supply();
    if supply == 0 {
        return 0;
    }

    let weight = storj.get_asset_weight(asset);

    // @TODO: check if asset balance needs to be `u256`
    // @TODO: check if this return cast is needed
    (weight * supply / storj.get_total_asset_weights()).as_u256()
}

#[storage(read, write)]
fn _collect_swap_fees(asset: AssetId, amount: u64, fee_basis_points: u64) -> u64 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let after_fee_amount = amount * (BASIS_POINTS_DIVISOR - fee_basis_points) / BASIS_POINTS_DIVISOR;
    let fee_amount = amount - after_fee_amount;

    let fee_reserve = storj.get_fee_reserves(asset);
    storj.write_fee_reserves(asset, fee_reserve + fee_amount.as_u256());

    // log(CollectSwapFees {
    //     asset,
    //     fee_usd: _asset_to_usd_min(asset, fee_amount.as_u256()),
    //     fee_assets: fee_amount,
    // });

    after_fee_amount
}

#[storage(read, write)]
fn _collect_margin_fees(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
    size_delta: u256,
    size: u256,
    entry_funding_rate: u256
) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let fee_usd: u256 = _get_position_fee(
        account,
        collateral_asset,
        index_asset,
        is_long,
        size_delta
    ) + _get_funding_fee(
        account,
        collateral_asset,
        index_asset,
        is_long,
        size,
        entry_funding_rate
    );

    let fee_assets = _usd_to_asset_min(collateral_asset, fee_usd);
    storj.write_fee_reserves(
        collateral_asset,
        storj.get_fee_reserves(collateral_asset) + fee_assets
    );

    // log(CollectMarginFees {
    //     asset: collateral_asset,
    //     fee_usd,
    //     fee_assets,
    // });

    return fee_usd;
}

#[storage(read)]
fn _get_redemption_amount(asset: AssetId, usdg_amount: u256) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let price = _get_max_price(asset);
    let redemption_amount = usdg_amount * PRICE_PRECISION / price;

    _adjust_for_decimals(redemption_amount, storj.get_usdg(), asset)
}

#[storage(read)]
fn _get_redemption_collateral(asset: AssetId) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    if storj.is_stable_asset(asset) {
        return storj.get_pool_amounts(asset);
    }

    let collateral = _usd_to_asset_min(
        asset,
        storj.get_guaranteed_usd(asset)
    );

    collateral + storj.get_pool_amounts(asset) - storj.get_reserved_amounts(asset)
}

#[storage(write)]
fn _update_asset_balance(asset: AssetId) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let next_balance = balance_of(contract_id(), asset);
    storj.write_asset_balances(asset, next_balance);
}

#[storage(read)]
fn _validate_buffer_amount(asset: AssetId) {
    let storj = abi(VaultStorage, storage.storj.read().into());
    
    let pool_amount = storj.get_pool_amounts(asset);
    let buffer_amount = storj.get_buffer_amounts(asset);

    if pool_amount < buffer_amount {
        require(false, Error::VaultPoolAmountLtBuffer);
    }
}

#[storage(read)]
fn _validate_router(account: Account) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let sender = get_sender();

    if sender == account || sender == Account::from(storj.get_router()) {
        return;
    }

    require(
        storj.is_approved_router(account, sender),
        Error::VaultInvalidMsgCaller
    );
}

fn _validate_position(size: u256, collateral: u256) {
    if size == 0 {
        require(
            collateral == 0,
            Error::VaultCollateralShouldBeWithdrawn
        );
        return;
    }

    require(
        size >= collateral,
        Error::VaultSizeMustBeMoreThanCollateral
    );
}

#[storage(read)]
fn _validate_assets(
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    if is_long {
        require(
            collateral_asset == index_asset,
            Error::VaultLongCollateralIndexAssetsMismatch
        );
        require(
            storj.is_asset_whitelisted(collateral_asset),
            Error::VaultLongCollateralAssetNotWhitelisted
        );
        require(
            !storj.is_stable_asset(collateral_asset),
            Error::VaultLongCollateralAssetMustNotBeStableAsset
        );

        return;
    }

    require(
        storj.is_asset_whitelisted(collateral_asset),
        Error::VaultShortCollateralAssetNotWhitelisted
    );
    require(
        storj.is_stable_asset(collateral_asset),
        Error::VaultShortCollateralAssetMustBeStableAsset
    );
    require(
        !storj.is_stable_asset(index_asset),
        Error::VaultShortIndexAssetMustNotBeStableAsset
    );
    require(
        storj.is_shortable_asset(index_asset),
        Error::VaultShortIndexAssetNotShortable
    );
}

fn _get_position_key(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
) -> b256 {
    keccak256(PositionKey {
        account,
        collateral_asset,
        index_asset,
        is_long,
    })
}

// note that if calling this function independently the cumulativeFundingRates 
// used in getFundingFee will not be the latest value
#[storage(read)]
fn _validate_liquidation(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
    should_raise: bool,
) -> (u256, u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let position_key = _get_position_key(
        account, 
        collateral_asset, 
        index_asset, 
        is_long
    );

    let position = storj.get_position(position_key);

    let (has_profit, delta) = _get_delta(
        index_asset,
        position.size,
        position.average_price,
        is_long,
        position.last_increased_time
    );

    let mut margin_fees: u256 = _get_funding_fee(
        account,
        collateral_asset,
        index_asset,
        is_long,
        position.size,
        position.entry_funding_rate
    ) + _get_position_fee(
        account,
        collateral_asset,
        index_asset,
        is_long,
        position.size,
    );

    if !has_profit && position.collateral < delta {
        if should_raise {
            require(false, Error::VaultLossesExceedCollateral);
        }

        return (1, margin_fees);
    }

    let mut remaining_collateral = position.collateral;
    if !has_profit {
        remaining_collateral = position.collateral - delta;
    }

    if remaining_collateral < margin_fees {
        if should_raise {
            require(false, Error::VaultFeesExceedCollateral);
        }

        // cap the fees to the remainingCollateral
        return (1, remaining_collateral);
    }

    if remaining_collateral < margin_fees + storj.get_liquidation_fee_usd() {
        if should_raise {
            require(false, Error::VaultLiquidationFeesExceedCollateral);
        }

        return (1, margin_fees);
    }

    if (remaining_collateral * storj.get_max_leverage().as_u256()) < (position.size * BASIS_POINTS_DIVISOR.as_u256()) {
        if should_raise {
            require(false, Error::VaultMaxLeverageExceeded);
        }

        return (2, margin_fees);
    }

    return (0, margin_fees);
}

// for longs:  next_average_price = (next_price * next_size) / (next_size + delta)
// for shorts: next_average_price = (next_price * next_size) / (next_size - delta)
#[storage(read)]
fn _get_next_average_price(
    index_asset: AssetId,
    size: u256,
    average_price: u256,
    is_long: bool,
    next_price: u256,
    size_delta: u256,
    last_increased_time: u64
) -> u256 {
    let (has_profit, delta) = _get_delta(
        index_asset,
        size,
        average_price,
        is_long,
        last_increased_time
    );

    let next_size = size + size_delta;
    let mut divisor = 0;
    if is_long {
        divisor = if has_profit { next_size + delta } else { next_size - delta }
    } else {
        divisor = if has_profit { next_size - delta } else { next_size + delta }
    }

    next_price * next_size / divisor
}

// for longs:  next_average_price = (next_price * next_size) / (next_size + delta)
// for shorts: next_average_price = (next_price * next_size) / (next_size - delta)
#[storage(read)]
fn _get_next_global_short_average_price(
    index_asset: AssetId,
    next_price: u256,
    size_delta: u256,
) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let size = storj.get_global_short_sizes(index_asset);
    let average_price = storj.get_global_short_average_prices(index_asset);
    let has_profit = average_price > next_price;

    let price_delta = if has_profit {
        average_price - next_price
    } else {
        next_price - average_price
    };

    let delta = size * price_delta / average_price; 

    let next_size = size + size_delta;

    let divisor = if has_profit {
        next_size - delta
    } else {
        next_size + delta
    };

    next_price * next_size / divisor
}

#[storage(read)]
fn _get_global_short_delta(asset: AssetId) -> (bool, u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let size = storj.get_global_short_sizes(asset);
    if size == 0 {
        return (false, 0);
    }

    let next_price = _get_max_price(asset);
    let average_price = storj.get_global_short_average_prices(asset);
    let has_profit = average_price > next_price;
    let price_delta = if has_profit {
        average_price - next_price
    } else {
        next_price - average_price
    };
    let delta = size * price_delta / average_price;
    (has_profit, delta)
}

#[storage(read)]
fn _get_position_delta(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    is_long: bool,
) -> (bool, u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let position_key = _get_position_key(
        account, 
        collateral_asset, 
        index_asset, 
        is_long
    );

    let position = storj.get_position(position_key);

    _get_delta(
        index_asset,
        position.size,
        position.average_price,
        is_long,
        position.last_increased_time
    )
}

#[storage(read)]
fn _get_delta(
    index_asset: AssetId,
    size: u256,
    average_price: u256,
    is_long: bool,
    last_increased_time: u64
) -> (bool, u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    require(average_price > 0, Error::VaultInvalidAveragePrice);

    let price = if is_long {
        _get_min_price(index_asset)
    } else {
        _get_max_price(index_asset)
    };

    let price_delta = if average_price > price {
        average_price - price
    } else {
        price - average_price
    };

    let mut delta = size * price_delta / average_price;

    let mut has_profit = false;
    if is_long {
        has_profit = price > average_price;
    } else {
        has_profit = average_price > price;
    }

    // if the minProfitTime has passed then there will be no min profit threshold
    // the min profit threshold helps to prevent front-running issues
    let min_bps = if timestamp() > last_increased_time + storj.get_min_profit_time() {
        0
    } else {
        storj.get_min_profit_basis_points(index_asset)
    };

    if has_profit
        && (delta * BASIS_POINTS_DIVISOR.as_u256()) <= (size * min_bps.as_u256())
    {
        delta = 0;
    }
    (has_profit, delta)
}

#[storage(read)]
fn _get_entry_funding_rate(
    collateral_asset: AssetId,
    _index_asset: AssetId,
    _is_long: bool,
) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    storj.get_cumulative_funding_rates(collateral_asset)
}

#[storage(read)]
fn _get_funding_fee(
    _account: Address,
    collateral_asset: AssetId,
    _index_asset: AssetId,
    _is_long: bool,
    size: u256,
    entry_funding_rate: u256
) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    if size == 0 {
        return 0;
    }

    let mut funding_rate = storj.get_cumulative_funding_rates(collateral_asset);
    funding_rate = funding_rate - entry_funding_rate;
    if funding_rate == 0 {
        return 0;
    }

    size * funding_rate / FUNDING_RATE_PRECISION
}

#[storage(read)]
fn _get_position_fee(
    _account: Address,
    _collateral_asset: AssetId,
    _index_asset: AssetId,
    _is_long: bool,
    size_delta: u256,
) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    if size_delta == 0 {
        return 0;
    }

    let mut after_fee_usd = size_delta * (BASIS_POINTS_DIVISOR - storj.get_margin_fee_basis_points()).as_u256();
    after_fee_usd = after_fee_usd / BASIS_POINTS_DIVISOR.as_u256();

    size_delta - after_fee_usd
}

#[storage(read, write)]
fn _decrease_position(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    collateral_delta: u256,
    size_delta: u256,
    is_long: bool,
    receiver: Account
) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    utils_validate_decrease_position(
        account,
        collateral_asset,
        index_asset,
        collateral_delta,
        size_delta,
        is_long,
        receiver
    );

    _update_cumulative_funding_rate(collateral_asset, index_asset);

    let position_key = _get_position_key(
        account, 
        collateral_asset, 
        index_asset, 
        is_long
    );
    let mut position = storj.get_position(position_key);
    require(position.size > 0, Error::VaultEmptyPosition);
    require(position.size >= size_delta, Error::VaultPositionSizeExceeded);
    require(position.collateral >= collateral_delta, Error::VaultPositionCollateralExceeded);

    let collateral = position.collateral;

    // scrop variables to prevent stack overflow errors (which aren't detected at compile-time)
    {
        let reserve_delta = position.reserve_amount * size_delta / position.size;
        position.reserve_amount = position.reserve_amount - reserve_delta;
        // update storage because the above changes are ignored by call to other fn `_reduce_collateral`
        storj.write_position(position_key, position);

        _decrease_reserved_amount(collateral_asset, reserve_delta);
    }
    
    let (usd_out, usd_out_after_fee) = _reduce_collateral(
        account,
        collateral_asset,
        index_asset,
        collateral_delta,
        size_delta,
        is_long
    );
    // re-initialize position here because storage was updated in `_reduce_collateral`
    position = storj.get_position(position_key);

    if position.size != size_delta {
        position.entry_funding_rate = _get_entry_funding_rate(collateral_asset, index_asset, is_long);
        position.size = position.size - size_delta;

        _validate_position(position.size, position.collateral);
        _validate_liquidation(
            account,
            collateral_asset,
            index_asset,
            is_long,
            true
        );

        if is_long {
            _increase_guaranteed_usd(collateral_asset, collateral - position.collateral);
            _decrease_guaranteed_usd(collateral_asset, size_delta);
        }

        let price = if is_long {
            _get_min_price(index_asset)
        } else {
            _get_max_price(index_asset)
        };

        // log(DecreasePosition {
        //     key: position_key,
        //     account,
        //     collateral_asset,
        //     index_asset,
        //     collateral_delta,
        //     size_delta,
        //     is_long,
        //     price,
        //     fee: usd_out - usd_out_after_fee,
        // });
        // log(UpdatePosition {
        //     key: position_key,
        //     size: position.size,
        //     collateral: position.collateral,
        //     average_price: position.average_price,
        //     entry_funding_rate: position.entry_funding_rate,
        //     reserve_amount: position.reserve_amount,
        //     realized_pnl: position.realized_pnl,
        //     mark_price: price,
        // });

        storj.write_position(position_key, position);
    } else {
        if is_long {
            _increase_guaranteed_usd(collateral_asset, collateral);
            _decrease_guaranteed_usd(collateral_asset, size_delta);
        }

        let price = if is_long {
            _get_min_price(index_asset)
        } else {
            _get_max_price(index_asset)
        };

        // log(DecreasePosition {
        //     key: position_key,
        //     account,
        //     collateral_asset,
        //     index_asset,
        //     collateral_delta,
        //     size_delta,
        //     is_long,
        //     price,
        //     fee: usd_out - usd_out_after_fee,
        // });
        // log(ClosePosition {
        //     key: position_key,
        //     size: position.size,
        //     collateral: position.collateral,
        //     average_price: position.average_price,
        //     entry_funding_rate: position.entry_funding_rate,
        //     reserve_amount: position.reserve_amount,
        //     realized_pnl: position.realized_pnl,
        // });

        storj.write_position(position_key, Position::default());
        position = storj.get_position(position_key);
    }

    if !is_long {
        _decrease_global_short_size(index_asset, size_delta);
    }

    if usd_out > 0 {
        if is_long {
            _decrease_pool_amount(collateral_asset, _usd_to_asset_min(collateral_asset, usd_out));
        }

        let amount_out_after_fees = _usd_to_asset_min(collateral_asset, usd_out_after_fee);
 
        // @TODO: potential revert here
        _transfer_out(collateral_asset, u64::try_from(amount_out_after_fees).unwrap(), receiver);
        
        storj.write_position(position_key, position);

        return amount_out_after_fees;
    }

    0
}

#[storage(read, write)]
fn _reduce_collateral(
    account: Address,
    collateral_asset: AssetId,
    index_asset: AssetId,
    collateral_delta: u256,
    size_delta: u256,
    is_long: bool,
) -> (u256, u256) {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let position_key = _get_position_key(
        account,
        collateral_asset,
        index_asset,
        is_long 
    );
    let mut position = storj.get_position(position_key);

    // scrop variables to prevent stack overflow errors (which aren't detected at compile-time)
    let mut fee = 0;
    let mut adjusted_delta = 0;
    let (mut has_profit, mut delta) = (false, 0);
    {
        fee = _collect_margin_fees(
            account,
            collateral_asset,
            index_asset,
            is_long,
            size_delta,
            position.size,
            position.entry_funding_rate
        );

        let (_has_profit, delta) = _get_delta(
            index_asset,
            position.size,
            position.average_price,
            is_long,
            position.last_increased_time
        );
        has_profit = _has_profit;

        adjusted_delta = size_delta * delta / position.size;
    }

    // transfer profits out
    let mut usd_out = 0;
    if adjusted_delta > 0 {
        if has_profit {
            usd_out = adjusted_delta;
            position.realized_pnl = position.realized_pnl + Signed256::from(adjusted_delta);

            // pay out realized profits from the pool amount for short positions
            if !is_long {
                let token_amount = _usd_to_asset_min(collateral_asset, adjusted_delta);
                _decrease_pool_amount(collateral_asset, token_amount);
            }
        } else {
            position.collateral = position.collateral - adjusted_delta;

            // transfer realized losses to the pool for short positions
            // realized losses for long positions are not transferred here as
            // _increasePoolAmount was already called in increasePosition for longs
            if !is_long {
                let token_amount = _usd_to_asset_min(collateral_asset, adjusted_delta);
                _increase_pool_amount(collateral_asset, token_amount);
            }

            position.realized_pnl = position.realized_pnl - Signed256::from(adjusted_delta);
        }
    }

    // reduce the position's collateral by _collateralDelta
    // transfer _collateralDelta out
    if collateral_delta > 0 {
        usd_out += collateral_delta;
        position.collateral = position.collateral - collateral_delta;
    }

    // if the position will be closed, then transfer the remaining collateral out
    if position.size == size_delta {
        usd_out += position.collateral;

        position.collateral = 0;
    }

    // if the usdOut is more than the fee then deduct the fee from the usdOut directly
    // else deduct the fee from the position's collateral
    let mut usd_out_after_fee = usd_out;
    if usd_out > fee {
        usd_out_after_fee = usd_out - fee;
    } else {
        position.collateral = position.collateral - fee;
        if is_long {
            let fee_assets = _usd_to_asset_min(collateral_asset, fee);
            _decrease_pool_amount(collateral_asset, fee_assets);
        }
    }

    storj.write_position(position_key, position);

    // log(UpdatePnl {
    //     key: position_key,
    //     has_profit,
    //     delta: adjusted_delta,
    // });
    (usd_out, usd_out_after_fee)
}

#[storage(read)]
fn _get_buy_usdg_fee_basis_points(
    asset: AssetId,
    usdg_amount: u256,
) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    _get_fee_basis_points(
        asset,
        usdg_amount,
        storj.get_mint_burn_fee_basis_points().as_u256(),
        storj.get_tax_basis_points().as_u256(),
        true
    )
}

#[storage(read)]
fn _get_sell_usdg_fee_basis_points(
    asset: AssetId,
    usdg_amount: u256
) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    _get_fee_basis_points(
        asset,
        usdg_amount,
        storj.get_mint_burn_fee_basis_points().as_u256(),
        storj.get_tax_basis_points().as_u256(),
        false
    )
}

#[storage(read)]
fn _get_swap_fee_basis_points(
    asset_in: AssetId,
    asset_out: AssetId,
    usdg_amount: u256
) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    let is_stableswap = storj.is_stable_asset(asset_in) && storj.is_stable_asset(asset_out);

    let base_bps = if is_stableswap {
        storj.get_stable_swap_fee_basis_points()
    } else {
        storj.get_swap_fee_basis_points()
    };

    let tax_bps = if is_stableswap {
        storj.get_stable_tax_basis_points()
    } else {
        storj.get_tax_basis_points()
    };

    let fee_basis_points_0 = _get_fee_basis_points(
        asset_in,
        usdg_amount,
        base_bps.as_u256(),
        tax_bps.as_u256(),
        true
    );
    let fee_basis_points_1 = _get_fee_basis_points(
        asset_out,
        usdg_amount,
        base_bps.as_u256(),
        tax_bps.as_u256(),
        false
    );

    // use the higher of the two fee basis points
    if fee_basis_points_0 > fee_basis_points_1 {
        fee_basis_points_0
    } else {
        fee_basis_points_1
    }
}

// cases to consider
// 1. `initial_amount` is far from `target_amount`, action increases balance slightly => high rebate
// 2. `initial_amount` is far from `target_amount`, action increases balance largely => high rebate
// 3. `initial_amount` is close to `target_amount`, action increases balance slightly => low rebate
// 4. `initial_amount` is far from `target_amount`, action reduces balance slightly => high tax
// 5. `initial_amount` is far from `target_amount`, action reduces balance largely => high tax
// 6. `initial_amount` is close to `target_amount`, action reduces balance largely => low tax
// 7. `initial_amount` is above `target_amount`, nextAmount is below `target_amount` and vice versa
// 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
#[storage(read)]
fn _get_fee_basis_points(
    asset: AssetId,
    usdg_delta: u256,
    fee_basis_points: u256,
    tax_basis_points: u256,
    should_increment: bool
) -> u256 {
    let storj = abi(VaultStorage, storage.storj.read().into());

    if !storj.has_dynamic_fees() {
        return fee_basis_points;
    }

    let initial_amount = storj.get_usdg_amount(asset);
    let mut next_amount = initial_amount + usdg_delta;
    if !should_increment {
        next_amount = if usdg_delta > initial_amount {
            0
        } else {
            initial_amount - usdg_delta
        };
    }

    let target_amount = _get_target_usdg_amount(asset);
    if target_amount == 0 {
        return fee_basis_points;
    }

    let initial_diff = if initial_amount > target_amount {
        initial_amount - target_amount
    } else {
        target_amount - initial_amount
    };

    let next_diff = if next_amount > target_amount {
        next_amount - target_amount
    } else {
        target_amount - next_amount
    };

    // action improves relative asset balance
    if next_diff < initial_diff {
        let rebate_bps = tax_basis_points * initial_diff / target_amount;
        return if rebate_bps > fee_basis_points {
            0
        } else {
            fee_basis_points - rebate_bps
        };
    }

    let mut avg_diff = (initial_diff + next_diff) / 2;
    if avg_diff > target_amount {
        avg_diff = target_amount;
    }

    let tax_bps = tax_basis_points * avg_diff / target_amount;
    
    fee_basis_points + tax_bps
}