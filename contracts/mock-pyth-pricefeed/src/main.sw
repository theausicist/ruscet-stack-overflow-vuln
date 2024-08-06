// SPDX-License-Identifier: Apache-2.0
contract;

/*
 __  __            _      ____        _   _       ____       _           __               _ 
|  \/  | ___   ___| | __ |  _ \ _   _| |_| |__   |  _ \ _ __(_) ___ ___ / _| ___  ___  __| |
| |\/| |/ _ \ / __| |/ / | |_) | | | | __| '_ \  | |_) | '__| |/ __/ _ \ |_ / _ \/ _ \/ _` |
| |  | | (_) | (__|   <  |  __/| |_| | |_| | | | |  __/| |  | | (_|  __/  _|  __/  __/ (_| |
|_|  |_|\___/ \___|_|\_\ |_|    \__, |\__|_| |_| |_|   |_|  |_|\___\___|_|  \___|\___|\__,_|
                                |___/
*/

mod errors;

use std::{
    block::timestamp,
    context::*,
    revert::require,
    storage::storage_string::*,
    string::String,
    bytes::*,
    bytes_conversions::{
        u64::*,
        b256::*,
        u256::*
    }
};
use std::hash::*;
use helpers::{context::*, utils::*, zero::*};
use interfaces::mock_pyth_pricefeed::{
    MockPythPricefeed,
    Price
};
use errors::*;

storage {
    is_initialized: bool = false,
    gov: Account = ZERO_ACCOUNT,

    // as a "mock" oracle, the Pyth Pricefeed Id for an asset is the `bits` value of the AssetId
    pyth_prices: StorageMap<b256, Price> = StorageMap::<b256, Price> {},
}

impl MockPythPricefeed for Contract {
    #[storage(read, write)]
    fn initialize(gov: Account) {
        require(
            !storage.is_initialized.read(),
            Error::MockPythPricefeedAlreadyInitialized
        );

        storage.is_initialized.write(true);
        storage.gov.write(gov);
    }

    /*
          ____ __     ___               
         / / / \ \   / (_) _____      __
        / / /   \ \ / /| |/ _ \ \ /\ / /
       / / /     \ V / | |  __/\ V  V / 
      /_/_/       \_/  |_|\___| \_/\_/  
    */
    #[storage(read)]
    fn price(pricefeed_id: b256) -> Price {
        let mut price = storage.pyth_prices.get(pricefeed_id).try_read().unwrap_or(Price::new());
        require(
            price.exponent != 0,
            Error::MockPythPricefeedPricefeedInfoNotSet
        );

        require(
            difference(timestamp(), price.publish_time) <= 60,
            Error::MockPythPricefeedStalePrice
        );

        price
    }

    #[storage(read)]
    fn price_no_older_than(time_period: u64, pricefeed_id: b256) -> Price {
        let mut price = storage.pyth_prices.get(pricefeed_id).try_read().unwrap_or(Price::new());
        require(
            price.exponent != 0,
            Error::MockPythPricefeedPricefeedInfoNotSet
        );

        require(
            difference(timestamp(), price.publish_time) <= time_period,
            Error::MockPythPricefeedStalePrice
        );

        price
    }

    /*
          ____     _       _           _       
         / / /    / \   __| |_ __ ___ (_)_ __  
        / / /    / _ \ / _` | '_ ` _ \| | '_ \ 
       / / /    / ___ \ (_| | | | | | | | | | |
      /_/_/    /_/   \_\__,_|_| |_| |_|_|_| |_|                         
    */
    #[storage(read, write)]
    fn set_pricefeed_config(
        pricefeed_id: b256,
        decimals: u32
    ) {
        require(get_sender() == storage.gov.read(), Error::MockPythPricefeedForbidden);

        storage.pyth_prices.insert(
            pricefeed_id,
            Price::from(0, decimals, 0, 0)
        );
    }

    /*
          ____  ____        _     _ _      
         / / / |  _ \ _   _| |__ | (_) ___ 
        / / /  | |_) | | | | '_ \| | |/ __|
       / / /   |  __/| |_| | |_) | | | (__ 
      /_/_/    |_|    \__,_|_.__/|_|_|\___|
    */
    // anyone can call this (this is only a MockPythPricefeed, after all)
    #[storage(read, write)]
    fn update_price_feed(update_data: Vec<Bytes>) {
        require(
            update_data.len() == 2,
            Error::MockPythPricefeedInvalidUpdateDataLen
        );

        let pricefeed_id = b256::from_le_bytes(update_data.get(0).unwrap());
        let new_price = u64::from_le_bytes(update_data.get(1).unwrap());

        let mut price = storage.pyth_prices.get(pricefeed_id).try_read().unwrap_or(Price::new());
        require(
            price.exponent != 0,
            Error::MockPythPricefeedPricefeedInfoNotSet
        );

        price.price = new_price;
        price.publish_time = timestamp();

        storage.pyth_prices.insert(pricefeed_id, price);
    }
}

fn difference(x: u64, y: u64) -> u64 {
    if x > y { x - y } else { y - x }
}