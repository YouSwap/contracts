// SPDX-License-Identifier: MIT

pragma solidity 0.7.4;

import './../interface/ITokenYou.sol';
import './../implement/YouswapInviteV1.sol';

/**
挖矿
 */
interface IYouswapFactoryV1 {
    
    /**
    用户挖矿信息
     */
    struct RewardInfo {
        uint256 receiveReward;//总领取奖励
        uint256 inviteReward;//总邀请奖励
        uint256 pledgeReward;//总质押奖励
    }

    /**
    质押用户信息
     */
    struct UserInfo {
        uint256 startBlock;//质押开始块高
        uint256 amount;//质押数量
        uint256 invitePower;//邀请算力
        uint256 pledgePower;//质押算力
        uint256 pendingReward;//待领取奖励
        uint256 inviteRewardDebt;//邀请负债
        uint256 pledgeRewardDebt;//质押负债
    }

    /**
    矿池信息（可视化）
     */
    struct PoolViewInfo {
        address lp;//LP地址
        string name;//名称
        uint256 multiple;//奖励倍数
        uint256 priority;//排序
    }

    /**
    矿池信息
     */
    struct PoolInfo {
        uint256 startBlock;//挖矿开始块高
        uint256 rewardTotal;//矿池总奖励
        uint256 rewardProvide;//矿池已发放奖励
        address lp;//lp合约地址
        uint256 amount;//质押数量
        uint256 lastRewardBlock;//最后发放奖励块高
        uint256 rewardPerBlock;//单个区块奖励
        uint256 totalPower;//总算力
        uint256 endBlock;//挖矿结束块高
        uint256 rewardPerShare;//单位算力奖励
    }

    ////////////////////////////////////////////////////////////////////////////////////
    
    /**
    自邀请
    self：Sender地址
     */
    event InviteRegister(address indexed self);

    /**
    更新矿池信息

    action：true(新建矿池)，false(更新矿池)
    pool：矿池序号
    lp：lp合约地址
    name：矿池名称
    startBlock：矿池开始挖矿块高
    rewardTotal：矿池总奖励
    rewardPerBlock：区块奖励
    multiple：矿池奖励倍数
    priority：矿池排序
     */
    event UpdatePool(bool action, uint256 pool, address indexed lp, string name, uint256 startBlock, uint256 rewardTotal, uint256 rewardPerBlock, uint256 multiple, uint256 priority);

    /**
    矿池挖矿结束
    
    pool：矿池序号
    lp：lp合约地址
     */
    event EndPool(uint256 pool, address indexed lp);
    
    /**
    质押

    pool：矿池序号
    lp：lp合约地址
    from：质押转出地址
    amount：质押数量
     */
    event Stake(uint256 pool, address indexed lp, address indexed from, uint256 amount);

    /**
    pool：矿池序号
    lp：lp合约地址
    totalPower：矿池总算力
    owner：用户地址
    ownerInvitePower：用户邀请算力
    ownerPledgePower：用户质押算力
    upper1：上1级地址
    upper1InvitePower：上1级邀请算力
    upper2：上2级地址
    upper2InvitePower：上2级邀请算力
     */
    event UpdatePower(uint256 pool, address lp, uint256 totalPower, address indexed owner, uint256 ownerInvitePower, uint256 ownerPledgePower, address indexed upper1, uint256 upper1InvitePower, address indexed upper2, uint256 upper2InvitePower);

    //算力

    /**
    解质押
    
    pool：矿池序号
    lp：lp合约地址
    to：解质押转入地址
    amount：解质押数量
     */
    event UnStake(uint256 pool, address indexed lp, address indexed to, uint256 amount);
    
    /**
    提取奖励

    pool：矿池序号
    lp：lp合约地址
    to：奖励转入地址
    amount：奖励数量
     */
    event WithdrawReward(uint256 pool, address indexed lp, address indexed to, uint256 amount);
    
    /**
    挖矿

    pool：矿池序号
    lp：lp合约地址
    amount：奖励数量
     */
    event Mint(uint256 pool, address indexed lp, uint256 amount);
    
    ////////////////////////////////////////////////////////////////////////////////////

    /**
    修改OWNER
     */
    function transferOwnership(address) external;

    /**
    设置YOU
     */
    function setYou(ITokenYou) external;

    /**
    设置邀请关系
     */
    function setInvite(YouswapInviteV1) external;
    
    /**
    质押
    */
    function deposit(uint256, uint256) external;
    
    /**
    解质押、提取奖励
     */
    function withdraw(uint256, uint256) external;

    /**
    矿池质押地址
     */
    function poolPledgeAddresss(uint256) external view returns (address[] memory);

    /**
    算力占比
     */
    function powerScale(uint256, address) external view returns (uint256);

    /**
    待领取的奖励
     */
    function pendingReward(uint256, address) external view returns (uint256);

    /**
    下级收益贡献
     */
    function rewardContribute(address, address) external view returns (uint256);

    /**
    个人收益加成
     */
    function selfReward(address) external view returns (uint256);

    /**
    通过lp查询矿池编号
     */
    function poolNumbers(address) external view returns (uint256[] memory);

    /**
    设置运营权限
     */
    function setOperateOwner(address, bool) external;

    ////////////////////////////////////////////////////////////////////////////////////    
    
    /**
    新建矿池
     */
    function addPool(string memory, address, uint256, uint256) external returns (bool);
        
    /**
    修改矿池区块奖励
     */
    function setRewardPerBlock(uint256, uint256) external;

    /**
    修改矿池总奖励
     */
    function setRewardTotal(uint256, uint256) external;

    /**
    修改矿池名称
     */
    function setName(uint256, string memory) external;
    
    /**
    修改矿池倍数
     */
    function setMultiple(uint256, uint256) external;
    
    /**
    修改矿池排序
     */
    function setPriority(uint256, uint256) external;
    
    ////////////////////////////////////////////////////////////////////////////////////
    
}