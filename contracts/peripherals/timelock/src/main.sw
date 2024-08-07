// SPDX-License-Identifier: Apache-2.0
contract;

/*
 _____ _                _            _    
|_   _(_)_ __ ___   ___| | ___   ___| | __
  | | | | '_ ` _ \ / _ \ |/ _ \ / __| |/ /
  | | | | | | | | |  __/ | (_) | (__|   < 
  |_| |_|_| |_| |_|\___|_|\___/ \___|_|\_\
*/

mod constants;
mod errors;

use std::{
    auth::msg_sender,
    block::timestamp,
    call_frames::{
        contract_id,
        msg_asset_id,
    },
    
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
use peripheral_interfaces::timelock::Timelock;
use referrals_interfaces::referral_storage::ReferralStorage;
use asset_interfaces::{
    glp::GLP,
    usdg::USDG
};
use core_interfaces::{
    vault_pricefeed::VaultPricefeed,
    base_position_manager::BasePositionManager,
    glp_manager::GLPManager,
    vault::Vault,
    vault_storage::VaultStorage
};
use helpers::{
    context::*, 
    utils::*,
    transfer::*,
    asset::*
};
use constants::*;
use errors::*;

storage {
    // gov is not restricted to an `Address` (EOA) or a `Contract` (external)
    // because this can be either a regular EOA (Address) or a Multisig (Contract)
    gov: Account = ZERO_ACCOUNT,

    buffer: u64 = 0,
    asset_manager: Account = ZERO_ACCOUNT,
    mint_receiver: Account = ZERO_ACCOUNT,
    glp_manager: ContractId = ZERO_CONTRACT,
    prev_glp_manager: ContractId = ZERO_CONTRACT,
    reward_router: ContractId = ZERO_CONTRACT,
    max_asset_supply: u64 = 0,
    margin_fee_bps: u64 = 0,
    max_margin_fee_bps: u64 = 0,

    should_toggle_is_leverage_enabled: bool = false,

    pending_actions: StorageMap<b256, u64> = StorageMap::<b256, u64> {},

    is_handler: StorageMap<Account, bool> = StorageMap::<Account, bool> {},
    is_keeper: StorageMap<Account, bool> = StorageMap::<Account, bool> {},
}

impl Timelock for Contract {
    #[storage(read, write)]
    fn initialize(
        gov: Account,
        buffer: u64,
        asset_manager: Account,
        mint_receiver: Account,
        glp_manager: ContractId,
        prev_glp_manager: ContractId,
        reward_router: ContractId,
        max_asset_supply: u64,
        margin_fee_bps: u64,
        max_margin_fee_bps: u64,
    ) {
        require(
            buffer <= MAX_BUFFER,
            Error::TimelockInvalidBuffer
        );

        storage.gov.write(gov);
        storage.buffer.write(buffer);
        storage.asset_manager.write(asset_manager);
        storage.mint_receiver.write(mint_receiver);
        storage.glp_manager.write(glp_manager);
        storage.prev_glp_manager.write(prev_glp_manager);
        storage.reward_router.write(reward_router);
        storage.max_asset_supply.write(max_asset_supply);

        storage.margin_fee_bps.write(margin_fee_bps);
        storage.max_margin_fee_bps.write(max_margin_fee_bps);
    }

    /*
          ____     _       _           _       
         / / /    / \   __| |_ __ ___ (_)_ __  
        / / /    / _ \ / _` | '_ ` _ \| | '_ \ 
       / / /    / ___ \ (_| | | | | | | | | | |
      /_/_/    /_/   \_\__,_|_| |_| |_|_|_| |_|                         
    */
    #[storage(read, write)]
    fn set_gov(gov: Account) {
        _only_asset_manager();
        
        storage.gov.write(gov);
    }

    #[storage(read)]
    fn set_external_admin(target: ContractId, admin: Account) {
        _only_gov();

        require(
            target != ContractId::this(),
            Error::TimelockInvalidTarget
        );
        
        abi(VaultStorage, target.into()).set_gov(admin);
    }

    #[storage(read, write)]
    fn set_contract_handler(handler: Account, is_active: bool) {
        _only_gov();
        
        storage.is_handler.insert(handler, is_active);
    }

    #[storage(read, write)]
    fn set_keeper(keeper: Account, is_active: bool) {
        _only_gov();
        
        storage.is_keeper.insert(keeper, is_active);
    }

    #[storage(read)]
    fn init_glp_manager() {
        _only_gov();

        let _glp_manager = storage.glp_manager.read();
        let glp_manager = abi(GLPManager, _glp_manager.into());
    
        let glp = abi(GLP, glp_manager.get_glp().into());
        glp.set_minter(Account::from(_glp_manager), true);

        let usdg = abi(USDG, glp_manager.get_usdg().into());
        usdg.add_vault(_glp_manager);

        let vault = abi(Vault, glp_manager.get_vault().into());
        abi(VaultStorage, vault.get_vault_storage().into()).set_manager(Account::from(_glp_manager), true);
    }

    // @TODO: uncomment when `RewardRouter` is implemented
    /*
    #[storage(read, write)]
    fn init_reward_router() {
        _only_gov();

        let _reward_router = storage.reward_router.read();
        let reward_router = abi(RewardRouter, _reward_router.into());

        abi(GLPManager, reward_router.get_fee_glp_tracker().into()).set_handler(_reward_router, true);
        abi(GLPManager, reward_router.get_staked_glp_tracker().into()).set_handler(_reward_router, true);
        abi(GLPManager, storage.glp_manager.read().into()).set_handler(_reward_router, true);
    }
    */

    #[storage(read, write)]
    fn set_buffer(buffer: u64) {
        _only_gov();

        require(
            buffer <= MAX_BUFFER,
            Error::TimelockInvalidBuffer
        );

        require(
            buffer < storage.buffer.read(),
            Error::TimelockBufferCannotBeDecreased
        );

        storage.buffer.write(buffer);
    }

    #[storage(read)]
    fn set_max_leverage(
        vault_storage: ContractId,
        max_leverage: u64
    ) {
        _only_gov();

        require(
            max_leverage > MAX_LEVERAGE_VALIDATION,
            Error::TimelockInvalidMaxLeverage
        );

        abi(VaultStorage, vault_storage.into()).set_max_leverage(max_leverage);
    }

    #[storage(read)]
    fn set_funding_rate(
        vault_storage: ContractId,
        funding_interval: u64,
        funding_rate_factor: u64,
        stable_funding_rate_factor: u64
    ) {
        _only_keeper_and_above();

        require(
            funding_rate_factor < MAX_FUNDING_RATE_FACTOR,
            Error::TimelockInvalidFundingRateFactor
        );

        require(
            stable_funding_rate_factor < MAX_FUNDING_RATE_FACTOR,
            Error::TimelockInvalidStableFundingRateFactor
        );

        abi(VaultStorage, vault_storage.into()).set_funding_rate(
            funding_interval,
            funding_rate_factor,
            stable_funding_rate_factor
        );
    }

    #[storage(read, write)]
    fn set_should_toggle_is_leverage_enabled(
        should_toggle_is_leverage_enabled: bool,
    ) {
        _only_handler_and_above();
        storage.should_toggle_is_leverage_enabled.write(should_toggle_is_leverage_enabled);
    }

    #[storage(read, write)]
    fn set_margin_fee_bps(
        margin_fee_bps: u64,
        max_margin_fee_bps: u64,
    ) {
        _only_handler_and_above();

        storage.margin_fee_bps.write(margin_fee_bps);
        storage.max_margin_fee_bps.write(max_margin_fee_bps);
    }

    #[storage(read)]
    fn set_swap_fees(
        vault_storage_: ContractId,
        tax_basis_points: u64,
        stable_tax_basis_points: u64,
        mint_burn_basis_points: u64,
        swap_fee_basis_points: u64,
        stable_swap_fee_basis_points: u64,
    ) {
        _only_keeper_and_above();

        let vault_storage = abi(VaultStorage, vault_storage_.into());

        vault_storage.set_fees(
            tax_basis_points,
            stable_tax_basis_points,
            mint_burn_basis_points,
            swap_fee_basis_points,
            stable_swap_fee_basis_points,
            storage.max_margin_fee_bps.read(),
            vault_storage.get_liquidation_fee_usd(),
            vault_storage.get_min_profit_time(),
            vault_storage.has_dynamic_fees()
        );
    }

    // assign _marginFeeBasisPoints to this.marginFeeBasisPoints
    // because enableLeverage would update Vault.marginFeeBasisPoints to this.marginFeeBasisPoints
    // and disableLeverage would reset the Vault.marginFeeBasisPoints to this.maxMarginFeeBasisPoints
    #[storage(read, write)]
    fn set_fees(
        vault_storage: ContractId,
        tax_basis_points: u64,
        stable_tax_basis_points: u64,
        mint_burn_basis_points: u64,
        swap_fee_basis_points: u64,
        stable_swap_fee_basis_points: u64,
        margin_fee_basis_points: u64,
        liquidation_fee_usd: u256,
        min_profit_time: u64,
        has_dynamic_fees: bool,
    ) {
        _only_keeper_and_above();

        storage.margin_fee_bps.write(margin_fee_basis_points);

        abi(VaultStorage, vault_storage.into()).set_fees(
            tax_basis_points,
            stable_tax_basis_points,
            mint_burn_basis_points,
            swap_fee_basis_points,
            stable_swap_fee_basis_points,
            storage.max_margin_fee_bps.read(),
            liquidation_fee_usd,
            min_profit_time,
            has_dynamic_fees
        );
    }

    #[storage(read)]
    fn enable_leverage(vault_storage_: ContractId) {
        _only_handler_and_above();

        let vault_storage = abi(VaultStorage, vault_storage_.into());

        if storage.should_toggle_is_leverage_enabled.read() {
            vault_storage.set_is_leverage_enabled(true);
        }

        vault_storage.set_fees(
            vault_storage.get_tax_basis_points(),
            vault_storage.get_stable_tax_basis_points(),
            vault_storage.get_mint_burn_fee_basis_points(),
            vault_storage.get_swap_fee_basis_points(),
            vault_storage.get_stable_swap_fee_basis_points(),
            storage.max_margin_fee_bps.read(),
            vault_storage.get_liquidation_fee_usd(),
            vault_storage.get_min_profit_time(),
            vault_storage.has_dynamic_fees()
        );
    }

    #[storage(read)]
    fn disable_leverage(vault_storage_: ContractId) {
        _only_handler_and_above();

        let vault_storage = abi(VaultStorage, vault_storage_.into());

        if storage.should_toggle_is_leverage_enabled.read() {
            vault_storage.set_is_leverage_enabled(false);
        }

        vault_storage.set_fees(
            vault_storage.get_tax_basis_points(),
            vault_storage.get_stable_tax_basis_points(),
            vault_storage.get_mint_burn_fee_basis_points(),
            vault_storage.get_swap_fee_basis_points(),
            vault_storage.get_stable_swap_fee_basis_points(),
            storage.max_margin_fee_bps.read(),
            vault_storage.get_liquidation_fee_usd(),
            vault_storage.get_min_profit_time(),
            vault_storage.has_dynamic_fees()
        );
    }

    #[storage(read)]
    fn set_is_leverage_enabled(vault_storage: ContractId, is_leverage_enabled: bool) {
        _only_handler_and_above();

        abi(VaultStorage, vault_storage.into()).set_is_leverage_enabled(is_leverage_enabled);
    }

    #[storage(read)]
    fn set_asset_config(
        vault_storage: ContractId,
        asset: AssetId,
        asset_weight: u64,
        min_profit_bps: u64,
        max_usdg_amount: u256,
        buffer_amount: u256,
        usdg_amount: u256,
    ) {
        _only_keeper_and_above();

        require(
            min_profit_bps <= 500,
            Error::TimelockInvalidMinProfitBps
        );

        let _vault_storage = abi(VaultStorage, vault_storage.into());

        require(
            _vault_storage.is_asset_whitelisted(asset),
            Error::TimelockAssetNotYetWhitelisted
        );


        let decimals = _vault_storage.get_asset_decimals(asset);

        _vault_storage.set_asset_config(
            asset,
            decimals,
            asset_weight,
            min_profit_bps,
            max_usdg_amount,
            _vault_storage.is_stable_asset(asset),
            _vault_storage.is_shortable_asset(asset)
        );

        _vault_storage.set_buffer_amount(asset, buffer_amount);
        _vault_storage.set_usdg_amount(asset, usdg_amount);
    }

    #[storage(read)]
    fn set_usdg_amounts(
        vault_storage: ContractId, 
        assets: Vec<AssetId>,
        usdg_amounts: Vec<u256>
    ) {
        _only_keeper_and_above();

        require(
            assets.len() == usdg_amounts.len(),
            Error::TimelockLengthMismatch
        );

        let _vault_storage = abi(VaultStorage, vault_storage.into());

        let mut i = 0;
        while i < assets.len() {
            _vault_storage.set_usdg_amount(
                assets.get(i).unwrap(),
                usdg_amounts.get(i).unwrap(),
            );

            i += 1;
        }
    }

    #[storage(read)]
    fn update_usdg_supply(glp_manager: ContractId, usdg_amount: u256) {
        _only_keeper_and_above();

        require(
            glp_manager == storage.glp_manager.read() || 
                glp_manager == storage.prev_glp_manager.read(),
            Error::TimelockInvalidGlpManager
        );

        let usdg = abi(USDG, abi(GLPManager, glp_manager.into()).get_usdg().into());
        let balance = usdg.balance_of(Account::from(glp_manager)).as_u256();

        usdg.add_vault(ContractId::this());

        if usdg_amount > balance {
            // @TODO: potential revert here
            let mint_amount = u64::try_from(usdg_amount - balance).unwrap();
            usdg.mint(Account::from(glp_manager), mint_amount);
        } else {
            // @TODO: potential revert here
            let burn_amount = u64::try_from(balance - usdg_amount).unwrap();
            // @TODO: do we need to forward the USDG to burn?
            usdg.burn(Account::from(glp_manager), burn_amount);
        }

        usdg.remove_vault(ContractId::this());
    }

    #[storage(read)]
    fn set_shorts_tracker_avg_price_weight(shorts_tracker_avg_price_weight: u64) {
        _only_gov();

        abi(GLPManager, storage.glp_manager.read().into()).set_shorts_tracker_avg_price_weight(
            shorts_tracker_avg_price_weight
        );
    }

    #[storage(read)]
    fn set_glp_cooldown_duration(glp_cooldown_duration: u64) {
        _only_gov();

        require(
            glp_cooldown_duration < (2 * 24 * 3600), // 2 days,
            Error::TimelockInvalidCooldownDuration
        );

        abi(GLPManager, storage.glp_manager.read().into()).set_cooldown_duration(
            glp_cooldown_duration
        );
    }

    #[storage(read)]
    fn set_max_global_short_size(
        vault_storage: ContractId,
        asset: AssetId,
        amount: u256
    ) {
        _only_gov();

        abi(VaultStorage, vault_storage.into()).set_max_global_short_size(
            asset, amount
        );
    }

    // @TODO: the asset contract needs to be passed, not the asset itself
    /*
    #[storage(read, write)]
    fn remove_admin(
        asset: AssetId,
        account: Account
    ) {
        _only_gov();

        abi(YieldAsset, asset.into()).remove_admin(account);
    }
    */

    #[storage(read)]
    fn set_is_swap_enabled(
        vault_storage: ContractId,
        is_swap_enabled: bool
    ) {
        _only_gov();

        abi(VaultStorage, vault_storage.into()).set_is_swap_enabled(is_swap_enabled);
    }

    #[storage(read)]
    fn set_tier(
        referral_storage: ContractId,
        tier_id: u64,
        total_rebate: u64,
        discount_share: u64
    ) {
        _only_keeper_and_above();

        abi(ReferralStorage, referral_storage.into()).set_tier(
            tier_id,
            total_rebate,
            discount_share
        );
    }

    #[storage(read)]
    fn set_referrer_tier(
        referral_storage: ContractId,
        referrer: Account,
        tier_id: u64,
    ) {
        _only_keeper_and_above();

        abi(ReferralStorage, referral_storage.into()).set_referrer_tier(
            referrer,
            tier_id,
        );
    }

    #[storage(read)]
    fn gov_set_codeowner(
        referral_storage: ContractId,
        code: b256,
        new_account: Account,
    ) {
        _only_keeper_and_above();

        abi(ReferralStorage, referral_storage.into()).gov_set_codeowner(
            code,
            new_account,
        );
    }

    #[storage(read)]
    fn withdraw_fees(
        vault: ContractId,
        asset: AssetId,
        receiver: Account
    ) {
        _only_gov();

        abi(Vault, vault.into()).withdraw_fees(asset, receiver);
    }

    #[storage(read)]
    fn batch_withdraw_fees(
        vault: ContractId,
        assets: Vec<AssetId>,
    ) {
        _only_keeper_and_above();

        let mut i = 0;
        let _vault = abi(Vault, vault.into());

        while i < assets.len() {
            _vault.withdraw_fees(assets.get(i).unwrap(), storage.gov.read());

            i += 1;
        }
    }

    #[storage(read)]
    fn set_in_private_liquidation_mode(
        vault_storage: ContractId,
        in_private_liquidation_mode: bool
    ) {
        _only_gov();

        abi(VaultStorage, vault_storage.into()).set_in_private_liquidation_mode(in_private_liquidation_mode);
    }

    #[storage(read)]
    fn set_liquidator(
        vault_storage: ContractId,
        liquidator: Account,
        is_active: bool
    ) {
        _only_gov();

        abi(VaultStorage, vault_storage.into()).set_liquidator(liquidator, is_active);
    }

    // @TODO: impl for `set_in_private_transfer_mode` for BaseToken
    /*
    #[storage(read, write)]
    fn set_in_private_transfer_mode(
        vault_storage: ContractId,
        in_private_liquidation_mode: bool
    ) {
        _only_gov();

        abi(VaultStorage, vault_storage.into()).set_in_private_transfer_mode(in_private_liquidation_mode);
    }
    */

    #[payable]
    fn transfer_in(
        _sender: Account,
        asset: AssetId,
        amount: u64
    ) {
        require(
            msg_asset_id() == asset,
            Error::TimelockInvalidAssetForwarded
        );

        require(
            msg_amount() == amount,
            Error::TimelockInvalidAmountForwarded
        );

        // no further logic required. Asset's are already transferred to the current contract
    }

    /*
          ____ __     ___               
         / / / \ \   / (_) _____      __
        / / /   \ \ / /| |/ _ \ \ /\ / /
       / / /     \ V / | |  __/\ V  V / 
      /_/_/       \_/  |_|\___| \_/\_/  
    */
    #[storage(read)]
    fn get_gov() -> Account {
        storage.gov.read()
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
    require(get_sender() == storage.gov.read(), Error::TimelockForbiddenNotGov);
}

#[storage(read)]
fn _only_asset_manager() {
    require(
        get_sender() == storage.asset_manager.read(), 
        Error::TimelockForbiddenNotAssetManager
    );
}

#[storage(read)]
fn _only_handler_and_above() {
    let sender = get_sender();

    require(
        sender == storage.gov.read() || 
        storage.is_handler.get(sender).try_read().unwrap_or(false),
        Error::TimelockForbiddenOnlyHandlerAndAbove
    );
}

#[storage(read)]
fn _only_keeper_and_above() {
    let sender = get_sender();

    require(
        sender == storage.gov.read() || 
        storage.is_handler.get(sender).try_read().unwrap_or(false) ||
        storage.is_keeper.get(sender).try_read().unwrap_or(false),
        Error::TimelockForbiddenOnlyKeeperAndAbove
    );
}