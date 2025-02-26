- 详细设计方案

- 1. 排行榜与NFT等级映射

- 

- **快照规则**：每日23:59（UTC）统计当月累计燃烧FATE总量，生成排行榜。

- **排名区间与等级**：

  | 排名区间     | NFT等级  | 名额   | 备注       |
  | ------------ | -------- | ------ | ---------- |
  | 1-10名       | Lv7 至尊 | 10人   | 顶级竞争者 |
  | 11-50名      | Lv6 神话 | 40人   | 高阶玩家   |
  | 51-100名     | Lv5 传奇 | 50人   | 中坚力量   |
  | 101-200名    | Lv4 史诗 | 100人  | 活跃玩家   |
  | 201-500名    | Lv3 稀有 | 300人  | 中级参与者 |
  | 501-1000名   | Lv2 精良 | 500人  | 入门竞争者 |
  | 1001名及以下 | Lv1 普通 | 无上限 | 默认等级   |

- **参与条件**：

  - 当月累计燃烧至少500 FATE进入排行榜，否则保持Lv1。

- **设计思路**：

  - 每日快照确保排名动态变化，激励持续投入。
  - 前10名稀缺性强，鼓励高额FATE燃烧。

- 2. NFT等级与临时权益（调整版）

- 

- **权益设计**（次日0:00至23:59有效）：

  | 等级     | 临时权益（24小时）                                 |
  | -------- | -------------------------------------------------- |
  | Lv1 普通 | 签到奖励+5%（100 FATE升至105 FATE）                |
  | Lv2 精良 | 签到+10%，占卜折扣10%（2,500 FATE降至2,250 FATE）  |
  | Lv3 稀有 | 签到+15%，占卜折扣15%，每日免费占卜1次             |
  | Lv4 史诗 | 签到+20%，占卜折扣20%，每日免费占卜2次             |
  | Lv5 传奇 | 签到+25%，占卜折扣25%，质押权重+10%                |
  | Lv6 神话 | 签到+30%，占卜折扣30%，质押权重+20%，任务奖励+50%  |
  | Lv7 至尊 | 签到+40%，占卜折扣40%，质押权重+30%，任务奖励+100% |

- **调整说明**：

  - **移除抽奖概率**：删除了Lv3-Lv7的抽奖概率加成（+5%、+10%、+15%、+20%、+25%）。
  - **权益优化**：
    - **签到奖励**：保持不变（+5%至+40%），提供基础吸引力。
    - **占卜折扣**：保持不变（10%至40%），与占卜玩法深度绑定。
    - **免费占卜**：Lv3新增1次免费占卜，Lv4提升至2次，填补抽奖概率移除的吸引力。
    - **质押权重**：Lv5 +10%、Lv6 +20%、Lv7 +30%，保持核心激励。
    - **任务奖励**：Lv6 +50%、Lv7 +100%，突出高等级差异性。
  - **权重提升**：
    - 不影响每日30M FATE总产出，仅调整用户分配比例。
    - Lv7 +30%确保顶级玩家有显著优势。

- **无永久增益**：

  - 所有权益每日刷新，次日根据新快照重新分配。

- **设计思路**：

  - 移除抽奖概率后，增加免费占卜次数强化占卜玩法吸引力。
  - 质押权重和任务奖励作为高等级核心激励，鼓励用户冲击前排名。

- 3. FATE燃烧与快照逻辑

- 

- **燃烧流程**：

  1. 用户调用burn_fate函数，燃烧任意数量FATE。
  2. 系统记录当月累计燃烧量，更新排行榜。
  3. 每日23:59快照，次日0:00分配NFT等级。

- **快照逻辑**：

  - 每日记录截止当时的燃烧总量，不清零月度数据。
  - 月末清零，次月重新开始。





功能表

| 函数名                  | 作用                                                         | 输入参数                                                     | 返回值      | 调用条件                                                     | 错误提示                                                     |
| ----------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ | ----------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| init                    | 初始化排行榜，设置默认配置（等级、档位、奖励）               | admin: &signer                                               | 无          | 仅管理员调用，合约部署时执行一次                             | 无                                                           |
| mint_usernft            | 为用户创建新的NFT，初始化默认值并同步排行榜end_time          | user: &signer                                                | 无          | 用户无NFT时，由burn_fate或snapshot调用                       | E_USER_ALREADY_EXISTS: "User NFT already exists"             |
| burn_fate               | 用户燃烧FATE，更新排行榜rankings和NFTburn_amount，10%入奖励池 | user: &signer, amount: u256                                  | 无          | 排行榜活跃（alive == true）                                  | E_LEADERBOARD_NOT_ALIVE: "Leaderboard is not active"         |
| snapshot_top_tiers      | 处理前1000名用户，更新NFT等级和权益，分配前100名奖励，延长周期 | _cap: &mut Object<AdminCap>, top_users: vector<address>, top_ranks: vector<u64> | 无          | 管理员调用，24小时间隔，alive == true，now <= end_time，输入长度匹配且≤1000 | E_LEADERBOARD_NOT_ALIVE, E_INVALID_INPUT_LENGTH, E_INVALID_TIMESTAMP |
| snapshot_others         | 处理1000名之后用户，更新NFT为Lv1，延长周期                   | _cap: &mut Object<AdminCap>, other_users: vector<address>    | 无          | 管理员调用，24小时间隔，alive == true，now <= end_time       | E_LEADERBOARD_NOT_ALIVE, E_INVALID_TIMESTAMP                 |
| get_level_from_rank     | 根据排名查找对应等级（从rank_tiers获取）                     | leaderboard: &Leaderboard, rank: u64                         | u64 (level) | 内部调用，无限制                                             | 无（默认返回1）                                              |
| update_nft              | 更新用户NFT的等级、权益和end_time                            | user: address, config: &LevelConfig, end_time: u64           | 无          | 内部调用，用户需有NFT                                        | 无（假定NFT存在）                                            |
| update_level_config     | 更新指定等级的权益配置（level_configs）                      | _cap: &mut Object<AdminCap>, level: u64, checkin_bonus: u64, market_discount: u64, free_tarot: u64, stake_weight: u64 | 无          | 管理员调用，等级存在                                         | E_LEVEL_NOT_FOUND: "Specified level not found in configs"    |
| update_rank_tier        | 更新排名档位配置（rank_tiers）                               | _cap: &mut Object<AdminCap>, tier_id: u64, min_rank: u64, max_rank: u64, level: u64 | 无          | 管理员调用，档位存在                                         | E_TIER_NOT_FOUND: "Specified tier not found in rank_tiers"   |
| update_top_reward_tier  | 更新前100名奖励百分比（top_reward_tiers）                    | _cap: &mut Object<AdminCap>, rank: u64, reward_percent: u64  | 无          | 管理员调用，rank <= 100，排名存在                            | E_TIER_NOT_FOUND, E_TOP_TIER_NOT_FOUND: "Top reward tier not found" |
| set_leaderboard_endtime | 设置排行榜周期结束时间，激活排行榜                           | _cap: &mut Object<AdminCap>, end_time: u64                   | 无          | 管理员调用，end_time需大于当前时间                           | E_INVALID_END_TIME: "End time must be in the future"         |

------

流程图

以下是代码的主要逻辑流程，展示用户燃烧FATE到排行榜更新和奖励分配的全过程：

```text
[用户] --> burn_fate(amount)
    |
    v
[检查NFT] --> 若无NFT --> mint_usernft --> 初始化NFT (end_time = leaderboard.end_time)
    |
    v
[燃烧FATE] --> 更新rankings & burn_amount
    |          --> 10%入reward_pool
    |          --> 90%销毁
    v
[链下排序] --> 获取rankings --> 排序 --> 分割前1000名和其他用户
    |
    v
[snapshot_top_tiers(top_users, top_ranks)]
    |          --> 更新NFT等级和end_time
    |          --> 前100名分配reward_pool按top_reward_tiers百分比
    |          --> 若接近end_time，延长30天，重置total_burned和reward_pool
    v
[snapshot_others(other_users)]
    |          --> 更新NFT为Lv1，同步end_time
    |          --> 若接近end_time，延长30天，重置total_burned和reward_pool
    v
[管理员调整] --> update_level_config / update_rank_tier / update_top_reward_tier / set_leaderboard_endtime
```

------

功能详细说明

1. **init**

- **作用**：初始化排行榜，设置默认等级配置、排名档位和前100名奖励百分比。
- **细节**：end_time默认30天后，alive设为true，total_burned和reward_pool为0。
- **mint_usernft**

- **作用**：为新用户创建NFT，初始化时同步排行榜end_time。
- **细节**：仅在用户无NFT时调用，避免重复创建。
- **burn_fate**

- **作用**：用户燃烧FATE，10%进入奖励池，90%销毁，更新rankings和NFTburn_amount。
- **细节**：需排行榜活跃，确保燃烧有意义。
- **snapshot_top_tiers**

- **作用**：处理前1000名用户，更新NFT等级和end_time，前100名按top_reward_tiers瓜分10%奖励池。
- **细节**：接近周期末时延长30天，重置total_burned和reward_pool。
- **snapshot_others**

- **作用**：处理1000名之后用户，更新NFT为Lv1，同步end_time，无奖励。
- **细节**：周期延长逻辑与snapshot_top_tiers一致。
- **get_level_from_rank**

- **作用**：根据排名查找对应等级，从rank_tiers获取。
- **细节**：内部函数，默认返回Lv1。
- **update_nft**

- **作用**：更新用户NFT的等级、权益和end_time。
- **细节**：假设NFT存在，直接修改。
- **update_level_config**

- **作用**：调整等级权益配置。
- **细节**：需等级存在，可随时调用。
- **update_rank_tier**

- **作用**：调整排名档位配置（仅等级）。
- **细节**：需档位存在，可动态调整。
- **update_top_reward_tier**

- **作用**：调整前100名奖励百分比。
- **细节**：需rank <= 100，确保顶级奖励可调。
- **set_leaderboard_endtime**

- **作用**：设置排行榜周期结束时间，激活排行榜。
- **细节**：end_time需未来时间，覆盖默认周期。

------

经济体系

- **每日流入**：35,935,000 FATE。
- **每日流出**：
  - 原有：22,950,000 FATE（含燃烧3.33M）。
  - 奖励（月燃烧100M）：10M/30 ≈ 333,333 FATE/天。
  - **总计**：23,283,333 FATE。
- **净流入**：12,651,667 FATE。
- **优化建议**：
  - 占卜2次/天，流出9,200,000，总流出29,483,333，净流入6,451,667 FATE。

------

总结

- **功能覆盖**：从初始化、燃烧FATE、排行榜更新到奖励分配，完整支持用户参与和管理员调整。
- **流程清晰**：链下排序+链上赋值，周期滚动，奖励动态。
- **激励与平衡**：10%奖励池、前100名瓜分，燃烧为主，奖励为辅。

你觉得这个总结表和流程清晰吗？需要补充或调整某部分吗？