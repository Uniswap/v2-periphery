const ethers = require('ethers');

const MNEMONIC = process.env.MNEMONIC;
const PROVIDER_ADDR = process.env.WEB3_PROVIDER_ADDR;
// address of the zero factory contract
const FACTORY_ADDR = process.env.FACTORY_ADDR;

(async () => {
    const provider = new ethers.providers.JsonRpcProvider(PROVIDER_ADDR);
    const wallet = ethers.Wallet.fromMnemonic(MNEMONIC).connect(provider);

    // in production, you need to use real wrapped eth | bnb | avax
    const wethFactory = ethers.ContractFactory.fromSolidity(require('./build/WETH9.json'), wallet);
    const wethContract = await wethFactory.deploy();
    console.log(`Test weth: https://testnet.bscscan.com/address/${wethContract.address}`);
    
    const router02Factory = ethers.ContractFactory.fromSolidity(require('./build/ZeroRouter02.json'), wallet);
    const router02Contract = await router02Factory.deploy(FACTORY_ADDR, wethContract.address);
    console.log(`Router02: https://testnet.bscscan.com/address/${router02Contract.address}`);

    // Deploy a couple of test ERC20 tokens and add liquidity
    const erc20Factory = ethers.ContractFactory.fromSolidity(require('./build/ERC20.json'), wallet);
    const erc20Contract1 = await erc20Factory.deploy(ethers.utils.parseEther('1000'));
    console.log(`First test ERC20: https://testnet.bscscan.com/address/${erc20Contract1.address}`);

    const erc20Contract2 = await erc20Factory.deploy(ethers.utils.parseEther('1000'));
    console.log(`Second est ERC20: https://testnet.bscscan.com/address/${erc20Contract2.address}`);

    await erc20Contract1.approve(router02Contract.address, ethers.utils.parseEther('1000'));
    await erc20Contract2.approve(router02Contract.address, ethers.utils.parseEther('1000'));

    const tokenA = erc20Contract1.address;
    const tokenB = erc20Contract2.address;
    const amountADesired = ethers.utils.parseEther('0.3');
    const amountBDesired = ethers.utils.parseEther('10');
    const amountAMin = ethers.utils.parseEther('0.001');
    const amountBMin = ethers.utils.parseEther('0.001');
    const to = wallet.address;
    const deadline = Math.floor(Date.now() / 1000) + 300;
    const tx = await router02Contract.addLiquidity(
        tokenA,
        tokenB,
        amountADesired,
        amountBDesired,
        amountAMin,
        amountBMin,
        to,
        deadline,
        {
            gasLimit: 3000000
        }
    );
    console.log(`Pair create tx: https://testnet.bscscan.com/tx/${tx.hash}`);
})();
