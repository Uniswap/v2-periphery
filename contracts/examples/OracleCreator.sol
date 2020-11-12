pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import './../libraries/TransferHelper.sol';
import './../libraries/DXswapOracleLibrary.sol';
import './../libraries/DXswapLibrary.sol';
import './../libraries/SafeMath.sol';

contract OracleCreator {
    using FixedPoint for *;
    using SafeMath for uint256;

    event OracleCreated(
        uint256 indexed _oracleIndex,
        address indexed _pair,
        uint256 _windowTime
    );

    struct Oracle{
        uint256 windowTime;
        address token0;
        address token1;
        IDXswapPair pair;
        uint32 blockTimestampLast;
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
        uint256 observationsCount;
        address owner;
    }

    mapping(uint256 => Oracle) public oracles;
    uint256 public oraclesIndex;

    function createOracle(
        uint256 windowTime,
        address pair
    ) public returns (uint256 oracleId) {
        IDXswapPair sourcePair = IDXswapPair(pair);
        address token0 = sourcePair.token0();
        address token1 = sourcePair.token1();
        (,, uint32 blockTimestampLast) =  sourcePair.getReserves();

        oracles[oraclesIndex] = Oracle({
            windowTime: windowTime,
            token0: token0,
            token1: token1,
            pair: sourcePair,
            blockTimestampLast: blockTimestampLast,
            price0CumulativeLast: sourcePair.price0CumulativeLast(),
            price1CumulativeLast: sourcePair.price1CumulativeLast(),
            price0Average: FixedPoint.uq112x112(0),
            price1Average: FixedPoint.uq112x112(0),
            observationsCount: 0,
            owner: msg.sender
        });
        oracleId = oraclesIndex;
        oraclesIndex++;
        emit OracleCreated(oracleId, address(sourcePair), windowTime);
    }

    function update(uint256 oracleIndex) public {
        Oracle storage oracle = oracles[oracleIndex];
        require(msg.sender == oracle.owner, 'OracleCreator: CALLER_NOT_OWNER');
        require(oracle.observationsCount < 2, 'OracleCreator: FINISHED_OBERSERVATION');
        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
            DXswapOracleLibrary.currentCumulativePrices(address(oracle.pair));
        uint32 timeElapsed = blockTimestamp - oracle.blockTimestampLast; // overflow is desired

        // first update can be executed immediately. Ensure that at least one full period has passed since the first update 
        require(
          oracle.observationsCount == 0 || timeElapsed >= oracle.windowTime, 
          'OracleCreator: PERIOD_NOT_ELAPSED'
        );

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        oracle.price0Average = FixedPoint.uq112x112(
          uint224((price0Cumulative - oracle.price0CumulativeLast) / timeElapsed)
        );
        oracle.price1Average = FixedPoint.uq112x112(
          uint224((price1Cumulative - oracle.price1CumulativeLast) / timeElapsed)
        );

        oracle.price0CumulativeLast = price0Cumulative;
        oracle.price1CumulativeLast = price1Cumulative;
        oracle.blockTimestampLast = blockTimestamp;
        oracle.observationsCount++;
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(uint256 oracleIndex, address token, uint256 amountIn) external view returns (uint256 amountOut) {
        Oracle storage oracle = oracles[oracleIndex];
        FixedPoint.uq112x112 memory avg;
        if (token == oracle.token0) { 
          avg = oracle.price0Average;
        } else {
          require(token == oracle.token1, 'OracleCreator: INVALID_TOKEN'); 
          avg = oracle.price1Average;
        }
        amountOut = avg.mul(amountIn).decode144();
    }

    function isOracleFinalized(uint256 oracleIndex) external view returns (bool){
        return oracles[oracleIndex].observationsCount == 2;
    }

    function getOracleDetails(uint256 oracleIndex) external view returns (Oracle memory) {
      return oracles[oracleIndex];
    }

}