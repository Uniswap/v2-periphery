pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import './OracleCreator.sol';
import './../interfaces/IDXswapFactory.sol';
import './../interfaces/IDXswapRouter.sol';
import './../libraries/TransferHelper.sol';
import './../interfaces/IERC20.sol';
import './../libraries/SafeMath.sol';
import './../libraries/DXswapLibrary.sol';

contract DXswapRelayer {
    using SafeMath for uint256;

    event NewOrder(
        uint256 indexed _orderIndex,
        uint8 indexed _action
    );

    event ExecutedOrder(
        uint256 indexed _orderIndex
    );

    event WithdrawnExpiredOrder(
        uint256 indexed _orderIndex
    );

    struct Order {
        uint8 action; // 1=provision; 2=removal
        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 amountB;
        uint256 liquidity;
        uint256 priceTolerance;
        uint256 minReserveA;
        uint256 minReserveB;
        address oraclePair;
        uint256 deadline;
        uint256 maxWindowTime;
        uint256 oracleId;
        address factory;
        bool executed;
    }

    uint256 public immutable GAS_ORACLE_UPDATE = 70000;
    uint256 public immutable PARTS_PER_MILLION = 1000000;
    uint256 public immutable BOUNTY = 0.01 ether;
    uint8 public immutable PROVISION = 1;
    uint8 public immutable REMOVAL = 2;

    address payable public immutable owner;
    address public immutable dxSwapFactory;
    address public immutable dxSwapRouter;
    address public immutable uniswapFactory;
    address public immutable uniswapRouter;
    address public immutable weth;

    OracleCreator oracleCreator;
    uint256 public orderCount;
    mapping(uint256 => Order) orders;

    constructor(
        address payable _owner,
        address _dxSwapFactory,
        address _dxSwapRouter,
        address _uniswapFactory,
        address _uniswapRouter,
        address _weth,
        OracleCreator _oracleCreater
    ) public {
        owner = _owner;
        dxSwapFactory = _dxSwapFactory;
        dxSwapRouter = _dxSwapRouter;
        uniswapFactory = _uniswapFactory;
        uniswapRouter = _uniswapRouter;
        weth = _weth;
        oracleCreator = _oracleCreater;
    }

    function orderLiquidityProvision(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 priceTolerance,
        uint256 minReserveA,
        uint256 minReserveB,
        uint256 maxWindowTime,
        uint256 deadline,
        address factory
    ) external payable returns (uint256 orderIndex) {
        require(factory == dxSwapFactory || factory == uniswapFactory, 'DXswapRelayer: INVALID_FACTORY');
        require(msg.sender == owner, 'DXswapRelayer: CALLER_NOT_OWNER');
        require(tokenA != tokenB, 'DXswapRelayer: INVALID_PAIR');
        require(tokenA < tokenB, 'DXswapRelayer: INVALID_TOKEN_ORDER');
        require(amountA > 0 && amountB > 0, 'DXswapRelayer: INVALID_TOKEN_AMOUNT');
        require(priceTolerance <= PARTS_PER_MILLION, 'DXswapRelayer: INVALID_TOLERANCE');
        require(block.timestamp <= deadline, 'DXswapRelayer: DEADLINE_REACHED');

        if (tokenA == address(0)) {
            require(msg.value >= amountA, 'DXswapRelayer: INSUFFIENT_ETH');
        } else {
            TransferHelper.safeTransferFrom(tokenA, owner, address(this), amountA);
        }
        TransferHelper.safeTransferFrom(tokenB, owner, address(this), amountB);

        address pair = _pair(tokenA, tokenB, factory);
        orderIndex = _OrderIndex();
        orders[orderIndex] = Order({
            action: PROVISION,
            tokenA: tokenA,
            tokenB: tokenB,
            amountA: amountA,
            amountB: amountB,
            liquidity: 0,
            priceTolerance: priceTolerance,
            minReserveA: minReserveA,
            minReserveB: minReserveB,
            oraclePair: pair,
            deadline: deadline,
            maxWindowTime: maxWindowTime,
            oracleId: 0,
            factory: factory,
            executed: false
        });
        emit NewOrder(orderIndex, PROVISION);

        (uint reserveA, uint reserveB,) = IDXswapPair(pair).getReserves();
        if (minReserveA == 0 && minReserveB == 0 && reserveA == 0 && reserveB == 0) {
            /* Non-circulating tokens can be provisioned immediately if reserve thresholds are set to zero */
            orders[orderIndex].executed = true;
            _pool(tokenA, tokenB, amountA, amountB, orders[orderIndex].amountA, orders[orderIndex].amountA);
            emit ExecutedOrder(orderIndex);
        } else {
            /* Create an oracle to calculate average price before providing liquidity */
            uint256 windowTime = _consultOracleParameters(amountA, amountB, reserveA, reserveB, maxWindowTime);
            orders[orderIndex].oracleId = oracleCreator.createOracle(windowTime, pair);
        }
    }

    function orderLiquidityRemoval(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountA,
        uint256 amountB,
        uint256 priceTolerance,
        uint256 minReserveA,
        uint256 minReserveB,
        uint256 maxWindowTime,
        uint256 deadline,
        address factory
    ) external returns (uint256 orderIndex) {
        require(factory == dxSwapFactory || factory == uniswapFactory, 'DXswapRelayer: INVALID_FACTORY');
        require(msg.sender == owner, 'DXswapRelayer: CALLER_NOT_OWNER');
        require(tokenA != tokenB, 'DXswapRelayer: INVALID_PAIR');
        require(tokenA < tokenB, 'DXswapRelayer: INVALID_TOKEN_ORDER');
        require(amountA > 0 && amountB > 0 && liquidity > 0, 'DXswapRelayer: INVALID_LIQUIDITY_AMOUNT');
        require(priceTolerance <= PARTS_PER_MILLION, 'DXswapRelayer: INVALID_TOLERANCE');
        require(block.timestamp <= deadline, 'DXswapRelayer: DEADLINE_REACHED');

        address pair = _pair(factory, tokenA, tokenB);
        orderIndex = _OrderIndex();
        orders[orderIndex] = Order({
            action: REMOVAL,
            tokenA: tokenA,
            tokenB: tokenB,
            amountA: amountA,
            amountB: amountB,
            liquidity: liquidity,
            priceTolerance: priceTolerance,
            minReserveA: minReserveA,
            minReserveB: minReserveB,
            oraclePair: pair,
            deadline: deadline,
            maxWindowTime: maxWindowTime,
            oracleId: 0,
            factory: factory,
            executed: false
        });

        address dxSwapPair = DXswapLibrary.pairFor(address(dxSwapFactory), tokenA, tokenB);
        (uint reserveA, uint reserveB,) = IDXswapPair(dxSwapPair).getReserves();
        uint256 windowTime = _consultOracleParameters(amountA, amountB, reserveA, reserveB, maxWindowTime);
        orders[orderIndex].oracleId = oracleCreator.createOracle(windowTime, pair);
        emit NewOrder(orderIndex, REMOVAL);
    }
    
    function executeOrder(uint256 orderIndex) external {
        Order storage order = orders[orderIndex];
        require(orderIndex <= orderCount && orderIndex != 0, 'DXswapRelayer: INVALID_ORDER');
        require(!order.executed, 'DXswapRelayer: ORDER_EXECUTED');
        require(oracleCreator.isOracleFinalized(order.oracleId) , 'DXswapRelayer: OBSERVATION_RUNNING');
        require(block.timestamp <= order.deadline, 'DXswapRelayer: DEADLINE_REACHED');

        address tokenA = order.tokenA;
        address tokenB = order.tokenB;
        uint256 amountB;
        amountB = oracleCreator.consult(
          order.oracleId,
          tokenA == address(0) ? IDXswapRouter(dxSwapRouter).WETH() : tokenA,
          order.amountA 
        );
        uint256 amountA = oracleCreator.consult(order.oracleId, tokenB, order.amountB);

        require(amountA <= order.amountA || amountB <= order.amountB, 'DXswapRelayer: INVALID PRICES');
        uint256 minA = amountA.sub(amountA.mul(order.priceTolerance) / PARTS_PER_MILLION);
        uint256 minB = amountB.sub(amountB.mul(order.priceTolerance) / PARTS_PER_MILLION);
        minA = minA <= order.amountA ? minA : 0;
        minB = minB <= order.amountB ? minB : 0;

        order.executed = true;
        if(order.action == PROVISION){
            _pool(tokenA, tokenB,  order.amountA, order.amountB, minA, minB);
        } else if (order.action == REMOVAL){
            address pair = _pair(tokenA, tokenB, dxSwapFactory);
            _unpool(
              tokenA, 
              tokenB, 
              pair, 
              order.liquidity,
              minA,
              minB
            );
        }
        emit ExecutedOrder(orderIndex);
    }

    function updateOracle(uint256 orderIndex) external {
        Order storage order = orders[orderIndex];
        require(block.timestamp < order.deadline, 'DXswapRelayer: DEADLINE_REACHED');
        require(!oracleCreator.isOracleFinalized(order.oracleId) , 'DXswapRelayer: OBSERVATION_ENDED');
        uint256 amountBounty = GAS_ORACLE_UPDATE.mul(tx.gasprice).add(BOUNTY);
        require(address(this).balance >= amountBounty, 'DXswapRelayer: INSUFFICIENT_BALANCE');
        (uint reserveA, uint reserveB,) = IDXswapPair(order.oraclePair).getReserves();
        require(
            reserveA >= order.minReserveA && reserveB >= order.minReserveB,
            'DXswapRelayer: RESERVE_TO_LOW'
        );
        oracleCreator.update(order.oracleId);
        TransferHelper.safeTransferETH(msg.sender, amountBounty);
    }

    function withdrawExpiredOrder(uint256 orderIndex) external {
        Order storage order = orders[orderIndex];
        require(block.timestamp > order.deadline, 'DXswapRelayer: DEADLINE_NOT_REACHED');
        require(order.executed == false, 'DXswapRelayer: ORDER_EXECUTED');
        address tokenA = order.tokenA;
        address tokenB = order.tokenB;
        uint256 amountA = order.amountA;
        uint256 amountB = order.amountB;
        order.executed = true;

        if (tokenA == address(0)) {
            TransferHelper.safeTransferETH(owner, amountA);
        } else {
            TransferHelper.safeTransfer(tokenA, owner, amountA);
        }
        TransferHelper.safeTransfer(tokenB, owner, amountB);
        emit WithdrawnExpiredOrder(orderIndex);
    }
    
    function _pool(
        address _tokenA,
        address _tokenB,
        uint256 _amountA,
        uint256 _amountB,
        uint256 _minA,
        uint256 _minB
    ) internal {
        uint256 amountA;
        uint256 amountB;
        uint256 liquidity;

        if (_tokenA != address(0) && _tokenB != address(0)) {
            TransferHelper.safeApprove(_tokenA, dxSwapRouter, _amountA);
            TransferHelper.safeApprove(_tokenB, dxSwapRouter, _amountB);
            (amountA, amountB, liquidity) = IDXswapRouter(dxSwapRouter).addLiquidity(
                _tokenA,
                _tokenB,
                _amountA,
                _amountB,
                _minA,
                _minB,
                owner,
                block.timestamp
            );
        } else {
            TransferHelper.safeApprove(_tokenB, dxSwapRouter, _amountB);
            (amountB, amountA, liquidity) = IDXswapRouter(dxSwapRouter).addLiquidityETH{
                value: _amountA
            }(_tokenB, _amountB, _minB, _minA, owner, block.timestamp);
        }
    }

    function _unpool(
        address _tokenA,
        address _tokenB,
        address _pair,
        uint256 _liquidity,
        uint256 _minA,
        uint256 _minB
    ) internal {
        uint amountA;
        uint amountB;

        if (_tokenA != address(0) && _tokenB != address(0)) {
            TransferHelper.safeApprove(_pair, dxSwapRouter, _liquidity);
            (amountA, amountB) = IDXswapRouter(dxSwapRouter).removeLiquidity(
                _tokenA,
                _tokenB,
                _liquidity,
                _minA,
                _minB,
                owner,
                block.timestamp
            );
        } else {
            TransferHelper.safeApprove(_tokenB, dxSwapRouter, _liquidity);
            (amountB, amountA) = IDXswapRouter(dxSwapRouter).removeLiquidityETH(
                _tokenB,
                _liquidity,
                _minB,
                _minA,
                owner,
                block.timestamp
            );
        }
    }

    function _consultOracleParameters(
        uint256 amountA,
        uint256 amountB,
        uint256 reserveA,
        uint256 reserveB,
        uint256 maxWindowTime
    ) internal view returns (uint256 windowTime) {
        if(reserveA > 0 && reserveB > 0){
            uint256 poolStake = (amountA.add(amountB)).mul(PARTS_PER_MILLION) / reserveA.add(reserveB);
            // poolStake: 0.1% = 1000; 1=10000; 10% = 100000;
            if(poolStake < 1000) {
              windowTime = 30;
            } else if (poolStake < 2500){
              windowTime = 60;
            } else if (poolStake < 5000){
              windowTime = 90;
            } else if (poolStake < 10000){
              windowTime = 120;
            } else {
              windowTime = 150;
            }
            windowTime = windowTime <= maxWindowTime ? windowTime : maxWindowTime;
        } else {
            windowTime = maxWindowTime;
        }
    }

    function _pair(address tokenA, address tokenB, address factory) internal view returns (address pair) {
      require(factory == dxSwapRouter || factory == uniswapRouter);
      if (tokenA == address(0)) tokenA = weth;
      pair = IDXswapFactory(factory).getPair(tokenA, tokenB);
    }

    function _OrderIndex() internal returns(uint256 orderIndex){
        orderIndex = orderCount;
        orderCount++;
    }

    function ERC20Withdraw(address token, uint256 amount) external {
        require(msg.sender == owner, 'DXswapRelayer: CALLER_NOT_OWNER');
        TransferHelper.safeTransfer(token, owner, amount);
    }

    function ETHWithdraw(uint256 amount) external {
        require(msg.sender == owner, 'DXswapRelayer: CALLER_NOT_OWNER');
        TransferHelper.safeTransferETH(owner, amount);
    }

    function GetOrderDetails(uint256 orderIndex) external view returns (Order memory) {
      return orders[orderIndex];
    }

    receive() external payable {}
}