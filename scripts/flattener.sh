mkdir contracts/.flattened
npx truffle-flattener contracts/DXswapRouter.sol > contracts/.flattened/DXswapRouter.sol
npx truffle-flattener contracts/libraries/DXswapLibrary.sol > contracts/.flattened/DXswapLibrary.sol
npx truffle-flattener contracts/libraries/DXswapOracleLibrary.sol > contracts/.flattened/DXswapOracleLibrary.sol
