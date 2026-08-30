// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {OrderType} from '../helpers/Enum.sol';

interface IAuction {
  function bidConfig() external view returns (address paymentToken, OrderType orderType);
  function finalized() external view returns (bool);
}

