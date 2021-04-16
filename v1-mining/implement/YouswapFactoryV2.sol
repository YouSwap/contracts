// SPDX-License-Identifier: MIT

pragma solidity 0.7.4;

import './../interface/IYouswapFactoryV2.sol';
import './../interface/IYouswapInviteV1.sol';
import './../interface/IYouswapAssetManagerV1.sol';
import './../library/ErrorCode.sol';
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract YouswapFactoryV2 is IYouswapFactoryV2 {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    uint256 public deployBlock;//合约部署块高
    address public owner;//所有权限
    mapping(address => bool) public operateOwner;//运营权限
    IYouswapAssetManagerV1 public assetManager;//
    YouswapInviteV1 public invite;//invite contract
    
    uint256 public poolCount = 0;//矿池数量
    mapping(address => RewardInfo) public rewardInfos;//用户挖矿信息
    mapping(uint256 => PoolInfo) public poolInfos;//矿池信息
    mapping(uint256 => PoolViewInfo) public poolViewInfos;//矿池信息
    mapping(uint256 => address[]) public pledgeAddresss;//矿池质押地址
    mapping(uint256 => mapping(address => UserInfo)) public pledgeUserInfo;//矿池质押用户信息

    uint256 public constant inviteSelfReward = 5;//质押自奖励，5%
    uint256 public constant invite1Reward = 15;//1级邀请奖励，15%
    uint256 public constant invite2Reward = 10;//2级邀请奖励，10%
    
    constructor (IYouswapAssetManagerV1 _assetManager, YouswapInviteV1 _invite) {
        deployBlock = block.number;
        owner = msg.sender;
        assetManager = _assetManager;
        invite = _invite;
        _setOperateOwner(owner, true);
    }

    ////////////////////////////////////////////////////////////////////////////////////

    function transferOwnership(address _owner) override external {
        require(owner == msg.sender, ErrorCode.FORBIDDEN);
        require((address(0) != _owner) && (owner != _owner), ErrorCode.INVALID_ADDRESSES);
        _setOperateOwner(owner, false);
        _setOperateOwner(_owner, true);
        owner = _owner;
    }
    
    function setInvite(YouswapInviteV1 _invite) override external {
        require(owner == msg.sender, ErrorCode.FORBIDDEN);
        invite = _invite;
    }
    
    function deposit(uint256 _pool, uint256 _amount) override external {
        require(0 < _amount, ErrorCode.FORBIDDEN);
        PoolInfo storage poolInfo = poolInfos[_pool];
        require((address(0) != poolInfo.lp) && (poolInfo.startBlock <= block.number), ErrorCode.MINING_NOT_STARTED);
        //require(0 == poolInfo.endBlock, ErrorCode.END_OF_MINING);
        (, uint256 startBlock) = invite.inviteUserInfoV2(msg.sender);
        if (0 == startBlock) {
            invite.register();
            
            emit InviteRegister(msg.sender);
        }

        IERC20(poolInfo.lp).safeTransferFrom(msg.sender, address(this), _amount);

        (address upper1, address upper2) = invite.inviteUpper2(msg.sender);

        computeReward(_pool);

        provideReward(_pool, poolInfo.rewardPerShare, poolInfo.lp, poolInfo.token, msg.sender, upper1, upper2);

        addPower(_pool, msg.sender, _amount, upper1, upper2);

        setRewardDebt(_pool, poolInfo.rewardPerShare, msg.sender, upper1, upper2);

        emit Stake(_pool, poolInfo.lp, msg.sender, _amount);
    }

    function withdraw(uint256 _pool, uint256 _amount) override external {
        PoolInfo storage poolInfo = poolInfos[_pool];
        require((address(0) != poolInfo.lp) && (poolInfo.startBlock <= block.number), ErrorCode.MINING_NOT_STARTED);
        if (0 < _amount) {
            UserInfo storage userInfo = pledgeUserInfo[_pool][msg.sender];
            require(_amount <= userInfo.amount, ErrorCode.BALANCE_INSUFFICIENT);
            IERC20(poolInfo.lp).safeTransfer(msg.sender, _amount);

            emit UnStake(_pool, poolInfo.lp, msg.sender, _amount);
        }

        (address _upper1, address _upper2) = invite.inviteUpper2(msg.sender);

        computeReward(_pool);

        provideReward(_pool, poolInfo.rewardPerShare, poolInfo.lp, poolInfo.token, msg.sender, _upper1, _upper2);

        if (0 < _amount) {
            subPower(_pool, msg.sender, _amount, _upper1, _upper2);
        }

        setRewardDebt(_pool, poolInfo.rewardPerShare, msg.sender, _upper1, _upper2);
    }

    function poolPledgeAddresss(uint256 _pool) override external view returns (address[] memory) {
        return pledgeAddresss[_pool];
    }

    function computeReward(uint256 _pool) internal {
        PoolInfo storage poolInfo = poolInfos[_pool];
        if ((0 < poolInfo.totalPower) && (poolInfo.rewardProvide < poolInfo.rewardTotal)) {
            uint256 reward = (block.number - poolInfo.lastRewardBlock).mul(poolInfo.rewardPerBlock);
            if (poolInfo.rewardProvide.add(reward) > poolInfo.rewardTotal) {
                reward = poolInfo.rewardTotal.sub(poolInfo.rewardProvide);
                poolInfo.endBlock = block.number;
            }
            
            poolInfo.rewardProvide = poolInfo.rewardProvide.add(reward);
            poolInfo.rewardPerShare = poolInfo.rewardPerShare.add(reward.mul(1e24).div(poolInfo.totalPower));
            poolInfo.lastRewardBlock = block.number;

            emit Mint(_pool, poolInfo.lp, reward);

            if (0 < poolInfo.endBlock) {
                emit EndPool(_pool, poolInfo.lp);
            }
        }
    }

    function addPower(uint256 _pool, address _user, uint256 _amount, address _upper1, address _upper2) internal {
        PoolInfo storage poolInfo = poolInfos[_pool];
        poolInfo.amount = poolInfo.amount.add(_amount);

        uint256 pledgePower = _amount;
        UserInfo storage userInfo = pledgeUserInfo[_pool][_user];            
        userInfo.amount = userInfo.amount.add(_amount);
        userInfo.pledgePower = userInfo.pledgePower.add(pledgePower);
        poolInfo.totalPower = poolInfo.totalPower.add(pledgePower);
        if (0 == userInfo.startBlock) {
            userInfo.startBlock = block.number;
            pledgeAddresss[_pool].push(msg.sender);
        }
        
        uint256 upper1InvitePower = 0;
        uint256 upper2InvitePower = 0;

        if (address(0) != _upper1) {
            uint256 inviteSelfPower = pledgePower.mul(inviteSelfReward).div(100);
            userInfo.invitePower = userInfo.invitePower.add(inviteSelfPower);
            poolInfo.totalPower = poolInfo.totalPower.add(inviteSelfPower);

            uint256 invite1Power = pledgePower.mul(invite1Reward).div(100);
            UserInfo storage upper1Info = pledgeUserInfo[_pool][_upper1];            
            upper1Info.invitePower = upper1Info.invitePower.add(invite1Power);
            upper1InvitePower = upper1Info.invitePower;
            poolInfo.totalPower = poolInfo.totalPower.add(invite1Power);
            if (0 == upper1Info.startBlock) {
                upper1Info.startBlock = block.number;
                pledgeAddresss[_pool].push(_upper1);
            }
        }

        if (address(0) != _upper2) {
            uint256 invite2Power = pledgePower.mul(invite2Reward).div(100);
            UserInfo storage upper2Info = pledgeUserInfo[_pool][_upper2];            
            upper2Info.invitePower = upper2Info.invitePower.add(invite2Power);
            upper2InvitePower = upper2Info.invitePower;
            poolInfo.totalPower = poolInfo.totalPower.add(invite2Power);
            if (0 == upper2Info.startBlock) {
                upper2Info.startBlock = block.number;
                pledgeAddresss[_pool].push(_upper2);
            }
        }
        
        emit UpdatePower(_pool, poolInfo.lp, poolInfo.totalPower, _user, userInfo.invitePower, userInfo.pledgePower, _upper1, upper1InvitePower, _upper2, upper2InvitePower);
    }

    function subPower(uint256 _pool, address _user, uint256 _amount, address _upper1, address _upper2) internal {
        PoolInfo storage poolInfo = poolInfos[_pool];
        UserInfo storage userInfo = pledgeUserInfo[_pool][_user];
        poolInfo.amount = poolInfo.amount.sub(_amount);

        uint256 pledgePower = _amount;
        userInfo.amount = userInfo.amount.sub(_amount);
        if (userInfo.pledgePower < pledgePower) {
            userInfo.pledgePower = 0;
        }else {
            userInfo.pledgePower = userInfo.pledgePower.sub(pledgePower);
        }
        if (poolInfo.totalPower < pledgePower) {
            poolInfo.totalPower = 0;
        }else {
            poolInfo.totalPower = poolInfo.totalPower.sub(pledgePower);
        }

        uint256 upper1InvitePower = 0;
        uint256 upper2InvitePower = 0;

        if (address(0) != _upper1) {
            uint256 inviteSelfPower = pledgePower.mul(inviteSelfReward).div(100);
            if (userInfo.invitePower < inviteSelfPower) {
                userInfo.invitePower = 0;
            }else {
                userInfo.invitePower = userInfo.invitePower.sub(inviteSelfPower);
            }
            if (poolInfo.totalPower < inviteSelfPower) {
                poolInfo.totalPower = 0;
            }else {
                poolInfo.totalPower = poolInfo.totalPower.sub(inviteSelfPower);
            }

            UserInfo storage upper1Info = pledgeUserInfo[_pool][_upper1];
            if (0 < upper1Info.startBlock) {
                uint256 invite1Power = pledgePower.mul(invite1Reward).div(100);
                if (upper1Info.invitePower < invite1Power) {
                    upper1Info.invitePower = 0;
                }else {
                    upper1Info.invitePower = upper1Info.invitePower.sub(invite1Power);
                }
                upper1InvitePower = upper1Info.invitePower;
                if (poolInfo.totalPower < invite1Power) {
                    poolInfo.totalPower = 0;
                }else {
                    poolInfo.totalPower = poolInfo.totalPower.sub(invite1Power);                    
                }

                if (address(0) != _upper2) {
                    UserInfo storage upper2Info = pledgeUserInfo[_pool][_upper2];
                    if (0 < upper2Info.startBlock) {
                        uint256 invite2Power = pledgePower.mul(invite2Reward).div(100);
                        if (upper2Info.invitePower < invite2Power) {
                            upper2Info.invitePower = 0;
                        }else {
                            upper2Info.invitePower = upper2Info.invitePower.sub(invite2Power);
                        }
                        upper2InvitePower = upper2Info.invitePower;
                        if (poolInfo.totalPower < invite2Power) {
                            poolInfo.totalPower = 0;
                        }else {
                            poolInfo.totalPower = poolInfo.totalPower.sub(invite2Power);
                        }
                    }
                }
            }
        }

        emit UpdatePower(_pool, poolInfo.lp, poolInfo.totalPower, _user, userInfo.invitePower, userInfo.pledgePower, _upper1, upper1InvitePower, _upper2, upper2InvitePower);        
    }

    function provideReward(uint256 _pool, uint256 _rewardPerShare, address _lp, address _token, address _user, address _upper1, address _upper2) internal {
        uint256 inviteReward = 0;
        uint256 pledgeReward = 0;
        UserInfo storage userInfo = pledgeUserInfo[_pool][_user];
        if ((0 < userInfo.invitePower) || (0 < userInfo.pledgePower)) {
            inviteReward = userInfo.invitePower.mul(_rewardPerShare).sub(userInfo.inviteRewardDebt).div(1e24);
            pledgeReward = userInfo.pledgePower.mul(_rewardPerShare).sub(userInfo.pledgeRewardDebt).div(1e24);

            userInfo.pendingReward = userInfo.pendingReward.add(inviteReward.add(pledgeReward));

            RewardInfo storage userRewardInfo = rewardInfos[_user];
            userRewardInfo.inviteReward = userRewardInfo.inviteReward.add(inviteReward);
            userRewardInfo.pledgeReward = userRewardInfo.pledgeReward.add(pledgeReward);
        }

        if (0 < userInfo.pendingReward) {
            assetManager.mint(_token, _user, userInfo.pendingReward);
            
            RewardInfo storage userRewardInfo = rewardInfos[_user];
            userRewardInfo.receiveReward = userRewardInfo.inviteReward;
            
            emit WithdrawReward(_pool, _lp, _user, userInfo.pendingReward);

            userInfo.pendingReward = 0;
        }

        if (address(0) != _upper1) {
            UserInfo storage upper1Info = pledgeUserInfo[_pool][_upper1];
            if ((0 < upper1Info.invitePower) || (0 < upper1Info.pledgePower)) {
                inviteReward = upper1Info.invitePower.mul(_rewardPerShare).sub(upper1Info.inviteRewardDebt).div(1e24);
                pledgeReward = upper1Info.pledgePower.mul(_rewardPerShare).sub(upper1Info.pledgeRewardDebt).div(1e24);
                
                upper1Info.pendingReward = upper1Info.pendingReward.add(inviteReward.add(pledgeReward));

                RewardInfo storage upper1RewardInfo = rewardInfos[_upper1];
                upper1RewardInfo.inviteReward = upper1RewardInfo.inviteReward.add(inviteReward);
                upper1RewardInfo.pledgeReward = upper1RewardInfo.pledgeReward.add(pledgeReward);
            }

            if (address(0) != _upper2) {
                UserInfo storage upper2Info = pledgeUserInfo[_pool][_upper2];
                if ((0 < upper2Info.invitePower) || (0 < upper2Info.pledgePower)) {
                    inviteReward = upper2Info.invitePower.mul(_rewardPerShare).sub(upper2Info.inviteRewardDebt).div(1e24);
                    pledgeReward = upper2Info.pledgePower.mul(_rewardPerShare).sub(upper2Info.pledgeRewardDebt).div(1e24);

                    upper2Info.pendingReward = upper2Info.pendingReward.add(inviteReward.add(pledgeReward));

                    RewardInfo storage upper2RewardInfo = rewardInfos[_upper2];
                    upper2RewardInfo.inviteReward = upper2RewardInfo.inviteReward.add(inviteReward);
                    upper2RewardInfo.pledgeReward = upper2RewardInfo.pledgeReward.add(pledgeReward);
                }
            }
        }
    }

    function setRewardDebt(uint256 _pool, uint256 _rewardPerShare, address _user, address _upper1, address _upper2) internal {
        UserInfo storage userInfo = pledgeUserInfo[_pool][_user];
        userInfo.inviteRewardDebt = userInfo.invitePower.mul(_rewardPerShare);
        userInfo.pledgeRewardDebt = userInfo.pledgePower.mul(_rewardPerShare);

        if (address(0) != _upper1) {
            UserInfo storage upper1Info = pledgeUserInfo[_pool][_upper1];
            upper1Info.inviteRewardDebt = upper1Info.invitePower.mul(_rewardPerShare);
            upper1Info.pledgeRewardDebt = upper1Info.pledgePower.mul(_rewardPerShare);

            if (address(0) != _upper2) {
                UserInfo storage upper2Info = pledgeUserInfo[_pool][_upper2];
                upper2Info.inviteRewardDebt = upper2Info.invitePower.mul(_rewardPerShare);
                upper2Info.pledgeRewardDebt = upper2Info.pledgePower.mul(_rewardPerShare);
            }
        }
    }
    
    function powerScale(uint256 _pool, address _user) override external view returns (uint256) {
        PoolInfo memory poolInfo = poolInfos[_pool];
        if (0 == poolInfo.totalPower) {
            return 0;
        }

        UserInfo memory userInfo = pledgeUserInfo[_pool][_user];
        return (userInfo.invitePower.add(userInfo.pledgePower).mul(100)).div(poolInfo.totalPower);
    }

    function pendingReward(uint256 _pool, address _user) override external view returns (uint256) {
        uint256 totalReward = 0;
        PoolInfo memory poolInfo = poolInfos[_pool];
        if (address(0) != poolInfo.lp && (poolInfo.startBlock <= block.number)) {
            uint256 rewardPerShare = 0;
            if (0 < poolInfo.totalPower) {
                uint256 reward = (block.number - poolInfo.lastRewardBlock).mul(poolInfo.rewardPerBlock);
                if (poolInfo.rewardProvide.add(reward) > poolInfo.rewardTotal) {
                    reward = poolInfo.rewardTotal.sub(poolInfo.rewardProvide);
                }
                rewardPerShare = reward.mul(1e24).div(poolInfo.totalPower);
            }
            rewardPerShare = rewardPerShare.add(poolInfo.rewardPerShare);

            UserInfo memory userInfo = pledgeUserInfo[_pool][_user];
            totalReward = userInfo.pendingReward;
            totalReward = totalReward.add(userInfo.invitePower.mul(rewardPerShare).sub(userInfo.inviteRewardDebt).div(1e24));
            totalReward = totalReward.add(userInfo.pledgePower.mul(rewardPerShare).sub(userInfo.pledgeRewardDebt).div(1e24));
        }

        return totalReward;
    }

    function rewardContribute(address _user, address _lower) override external view returns (uint256) {
        if ((address(0) == _user) || (address(0) == _lower)) {
            return 0;
        }

        uint256 inviteReward = 0;
        (address upper1, address upper2) = invite.inviteUpper2(_lower);
        if (_user == upper1) {
            inviteReward = rewardInfos[_lower].pledgeReward.mul(invite1Reward).div(100);
        }else if (_user == upper2) {
            inviteReward = rewardInfos[_lower].pledgeReward.mul(invite2Reward).div(100);
        }
        
        return inviteReward;
    }

    function selfReward(address _user) override external view returns (uint256) {
        address upper1 = invite.inviteUpper1(_user);
        if (address(0) == upper1) {
            return 0;
        }

        RewardInfo memory userRewardInfo = rewardInfos[_user];
        return userRewardInfo.pledgeReward.mul(inviteSelfReward).div(100);
    }

    function poolNumbers(address _lp) override external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < poolCount; i++) {
            if (_lp == poolViewInfos[i].lp) {
                count = count.add(1);
            }
        }
        
        uint256[] memory numbers = new uint256[](count);
        count = 0;
        for (uint256 i = 0; i < poolCount; i++) {
            if (_lp == poolViewInfos[i].lp) {
                numbers[count] = i;
                count = count.add(1);
            }
        }

        return numbers;
    }

    function setOperateOwner(address _address, bool _bool) override external {
        _setOperateOwner(_address, _bool);
    }
    
    function _setOperateOwner(address _address, bool _bool) internal {
        require(owner == msg.sender, ErrorCode.FORBIDDEN);
        operateOwner[_address] = _bool;
    }

    ////////////////////////////////////////////////////////////////////////////////////

    function addPool(string memory _name, address _lp, uint256 _startBlock, uint256 _zone, uint256 _multiple, address _token, uint256 _rewardPerBlock, uint256 _rewardTotal) override external returns (bool) {
        require(operateOwner[msg.sender] && (address(0) != _lp) && (address(this) != _lp), ErrorCode.FORBIDDEN);
        require(_rewardPerBlock <= _rewardTotal, ErrorCode.FORBIDDEN);
        _startBlock = _startBlock < block.number ? block.number : _startBlock;
        uint256 _pool = poolCount;
        poolCount = poolCount.add(1);

        PoolViewInfo storage poolViewInfo = poolViewInfos[_pool];
        poolViewInfo.lp = _lp;
        poolViewInfo.token = _token;
        poolViewInfo.name = _name;
        poolViewInfo.multiple = _multiple;
        poolViewInfo.priority = _pool.mul(100).add(50);
        poolViewInfo.zone = _zone;
        
        PoolInfo storage poolInfo = poolInfos[_pool];
        poolInfo.startBlock = _startBlock;
        poolInfo.rewardTotal = _rewardTotal;
        poolInfo.rewardProvide = 0;
        poolInfo.lp = _lp;
        poolInfo.token = _token;
        poolInfo.amount = 0;
        poolInfo.lastRewardBlock = _startBlock.sub(1);
        poolInfo.rewardPerBlock = _rewardPerBlock;
        poolInfo.totalPower = 0;
        poolInfo.endBlock = 0;
        poolInfo.rewardPerShare = 0;

        emit UpdatePool(true, _pool, poolInfo.lp, poolViewInfo.name, poolInfo.startBlock, poolInfo.rewardTotal, poolInfo.rewardPerBlock, poolViewInfo.multiple, poolViewInfo.priority, poolViewInfo.zone);

        return true;
    }
    
    function setRewardPerBlock(uint256 _pool, uint256 _rewardPerBlock) override external {
        require(operateOwner[msg.sender], ErrorCode.FORBIDDEN);
        PoolInfo storage poolInfo = poolInfos[_pool];
        require((address(0) != poolInfo.lp) && (0 == poolInfo.endBlock), ErrorCode.POOL_NOT_EXIST_OR_END_OF_MINING);
        
        computeReward(_pool);
        
        poolInfo.rewardPerBlock = _rewardPerBlock;

        PoolViewInfo memory poolViewInfo = poolViewInfos[_pool];

        emit UpdatePool(false, _pool, poolInfo.lp, poolViewInfo.name, poolInfo.startBlock, poolInfo.rewardTotal, poolInfo.rewardPerBlock, poolViewInfo.multiple, poolViewInfo.priority, poolViewInfo.zone);
    }
    
    function setRewardTotal(uint256 _pool, uint256 _rewardTotal) override external {
        require(operateOwner[msg.sender], ErrorCode.FORBIDDEN);
        PoolInfo storage poolInfo = poolInfos[_pool];
        require((address(0) != poolInfo.lp) && (0 == poolInfo.endBlock), ErrorCode.POOL_NOT_EXIST_OR_END_OF_MINING);

        computeReward(_pool);
        
        require(poolInfo.rewardProvide < _rewardTotal, ErrorCode.REWARDTOTAL_LESS_THAN_REWARDPROVIDE);
        
        poolInfo.rewardTotal = _rewardTotal;

        PoolViewInfo memory poolViewInfo = poolViewInfos[_pool];

        emit UpdatePool(false, _pool, poolInfo.lp, poolViewInfo.name, poolInfo.startBlock, poolInfo.rewardTotal, poolInfo.rewardPerBlock, poolViewInfo.multiple, poolViewInfo.priority, poolViewInfo.zone);
   }

   function setName(uint256 _pool, string memory _name) override external {
        require(operateOwner[msg.sender], ErrorCode.FORBIDDEN);
        PoolViewInfo storage poolViewInfo = poolViewInfos[_pool];
        require(address(0) != poolViewInfo.lp, ErrorCode.POOL_NOT_EXIST_OR_END_OF_MINING);
        poolViewInfo.name = _name;

        PoolInfo memory poolInfo = poolInfos[_pool];

        emit UpdatePool(false, _pool, poolInfo.lp, poolViewInfo.name, poolInfo.startBlock, poolInfo.rewardTotal, poolInfo.rewardPerBlock, poolViewInfo.multiple, poolViewInfo.priority, poolViewInfo.zone);
   }

   function setMultiple(uint256 _pool, uint256 _multiple) override external {
        require(operateOwner[msg.sender], ErrorCode.FORBIDDEN);
        PoolViewInfo storage poolViewInfo = poolViewInfos[_pool];
        require(address(0) != poolViewInfo.lp, ErrorCode.POOL_NOT_EXIST_OR_END_OF_MINING);
        poolViewInfo.multiple = _multiple;

        PoolInfo memory poolInfo = poolInfos[_pool];

        emit UpdatePool(false, _pool, poolInfo.lp, poolViewInfo.name, poolInfo.startBlock, poolInfo.rewardTotal, poolInfo.rewardPerBlock, poolViewInfo.multiple, poolViewInfo.priority, poolViewInfo.zone);
    }

    function setPriority(uint256 _pool, uint256 _priority) override external {
        require(operateOwner[msg.sender], ErrorCode.FORBIDDEN);
        PoolViewInfo storage poolViewInfo = poolViewInfos[_pool];
        require(address(0) != poolViewInfo.lp, ErrorCode.POOL_NOT_EXIST_OR_END_OF_MINING);
        poolViewInfo.priority = _priority;

        PoolInfo memory poolInfo = poolInfos[_pool];

        emit UpdatePool(false, _pool, poolInfo.lp, poolViewInfo.name, poolInfo.startBlock, poolInfo.rewardTotal, poolInfo.rewardPerBlock, poolViewInfo.multiple, poolViewInfo.priority, poolViewInfo.zone);
    }

    function setZone(uint256 _pool, uint256 _zone) override external {
        require(operateOwner[msg.sender], ErrorCode.FORBIDDEN);
        PoolViewInfo storage poolViewInfo = poolViewInfos[_pool];
        require(address(0) != poolViewInfo.lp, ErrorCode.POOL_NOT_EXIST_OR_END_OF_MINING);
        poolViewInfo.zone = _zone;

        PoolInfo memory poolInfo = poolInfos[_pool];

        emit UpdatePool(false, _pool, poolInfo.lp, poolViewInfo.name, poolInfo.startBlock, poolInfo.rewardTotal, poolInfo.rewardPerBlock, poolViewInfo.multiple, poolViewInfo.priority, poolViewInfo.zone);
    }

    ////////////////////////////////////////////////////////////////////////////////////

}