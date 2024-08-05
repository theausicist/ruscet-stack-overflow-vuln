# The Ruscet Protocol Contracts

## License

Protected under Apache-2.0 license ([Burra Labs](https://github.com/burralabs))

## Reproduce error

Error in `contracts/core/vault/src/main.sw`: search for line 1156: `fn _increase_reserved_amount(asset: AssetId, amount: u256) {`

```bash
# Install
yarn

# Copy contents of `patched-index.js` to `node_modules/@fuels-ts/program/dist/index.js`
# ^^^^^^^^^^^^^^^^^^^^^^^
# ^^^^^^^^^^^^^^^^^^^^^^^

# Compile contracts
forc build --release --log-level 4

# Generate types
yarn gen:types

# In separate terminal, run the fuel node
fuel-core run --chain ./chainConfig.json --db-type in-memory

# Run tests
yarn test:specific
```

## Random seed phrase

```bash
basic marriage medal ship cube stove anxiety couple limit camera lawsuit inch

Addr: 0x0d1ead21b8a47fb6d6a350c28a432c3e217aa961a98c8991254a98122f3502b6
Priv: 0x0cb77a9a1a5ef503bd004e18dfca37abde2622686acede5fd2416f7bd04db231

Acc 2: 0x99b5525030f9aa1ebcd54f257fd9abd62604bf399410b60fb8e65748167475a3
Priv: 0x900a3a497efec790f18e911657300b3104982f3ec08fc86dae9981d4b5b67dce

Acc 3: 0xb232b9c6bf8b87f0741585b22b56d309da9789d8a4e1d43cc1deff65ac7fee40
Priv: 0x2a620587fd74c8f6c660cab3080b286dfb4dabd0388a0653ca195a1634b23053

Acc 4: 0x8c5acd8cbbbbb69cd5c15009c099fab7045889a54bc757ec710b49b58ce04628
Priv: 0x6dbcac934e1c794d76016ab34046c24cfdfcfc98eb60a97d72db20406efabc65

Acc 5: 0xd1bc0b388738d652800e7f76ef1874660a9f3400f3fd5cd9290fcb5090a01602
Priv: 0x11311480688c8dec476355efb90682c83a2fb9f5e6a5e9cb37de61756d186a83
```
