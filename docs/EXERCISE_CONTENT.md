# NeckEase Exercise Content / 颈间动作内容

Routine version / 内容版本: `neck-ease-v1.0`

App release / App 版本: `v0.1.0-beta.1`

## Purpose / 用途

**English:** NeckEase is a short movement break for general adult office use. It is designed to make regular movement easier to remember and follow. It is not a medical device, diagnostic tool, treatment, or individualized rehabilitation plan.

**中文：**颈间是面向一般成年办公人群的短时活动提醒，目的是让日常活动更容易被记住和跟随。它不是医疗器械、诊断工具、治疗方案或个体化康复计划。

Move slowly within a comfortable range. Stop if a movement causes discomfort.

请在舒适范围内缓慢完成；如果动作引起不适，请停止。

## Routine / 动作方案

| Movement | UI name | Guidance | Product dose | Camera signal |
|---|---|---|---:|---|
| Neck rotation | 左右缓慢转头 | Sit upright, relax the shoulders, turn toward the prompted side, pause briefly, and return to neutral. Do not lean back or chase a maximum angle. | 4 each side | yaw |
| Lateral flexion | 左右轻柔侧屈 | Face forward, bring the ear gently toward the prompted shoulder, pause, and return to neutral. Do not lift the shoulder or press the head with a hand. | 3 each side | roll |
| Gentle nod | 轻柔低头并回正 | With relaxed shoulders, make a small, slow nod, pause briefly, and return to natural neutral. Do not extend backward or force the chin toward the chest. | 5 total | pitch |

The dose above is the beta's product routine, not a treatment prescription. The app does not evaluate spinal structures, muscle recruitment, or clinical movement quality.

以上次数是 Beta 的产品动作方案，不是治疗处方。App 不评价椎体结构、肌肉发力或医疗意义上的动作质量。

## Counting contract / 计次规则

Every camera-counted repetition requires:

1. a stable neutral position;
2. movement in the expected direction;
3. reaching the recognition threshold;
4. at least 300 ms at the target;
5. a visible return to neutral and at least 300 ms there.

每次摄像头计次都必须包含：稳定中立位、正确方向、达到识别阈值、到位至少保持 300 ms，以及可见地回到中立位并保持至少 300 ms。

Rotation and lateral flexion use conservative recognition thresholds relative to the user's calibrated neutral pose: 15° yaw and 9° roll. Gentle nod uses 60% of the stable demonstration peak, clamped to 5–8° pitch. These values are approximate camera-recognition thresholds. They are not medical range-of-motion targets, required exercise amplitude, or a judgment of whether a movement is “correct.”

转头和侧屈使用相对个人中立位的保守识别阈值：yaw 15°、roll 9°。轻柔低头使用稳定示范峰值的 60%，并限制在 pitch 5–8°。这些数值只是近似的摄像头识别阈值，不是医学活动度目标、必须达到的动作幅度，也不用于判断动作是否“标准”。

If recognition is unreliable, the app should offer manual counting rather than ask the user to move farther.

如果识别不稳定，App 应提供手动计次，而不是要求用户增大动作幅度。

## Evidence boundary / 依据与边界

The routine uses familiar low-intensity neck-mobility patterns and frequent short-break principles. Public references used when shaping the beta content include:

- [NHS cervical spine mobility exercises](https://plr.cht.nhs.uk/download/902/Neck%20Exercises%20-%20Mobilising%20Exercises)
- [HSE guidance on display-screen breaks](https://www.hse.gov.uk/contact/faqs/vdubreaks.htm)
- [2024 systematic review of exercise for office workers with chronic neck pain](https://pubmed.ncbi.nlm.nih.gov/38219373/)

These sources support staying active and studying exercise interventions, but they do not establish that this exact three-minute routine treats neck pain or works equally for everyone. MellowDesk makes no such claim. The wording and illustrations in this repository must remain original; a reference link does not grant permission to copy third-party text or images.

这些资料支持保持活动，并讨论办公人群运动干预，但不能证明本产品这套约三分钟动作可以治疗颈痛，也不能证明它对每个人效果相同。小桌伴不作此类宣称。仓库中的文案和插图必须保持原创；引用链接不代表可以复制第三方原文或图片。

## Content status / 内容状态

| Version | Maintainer review | Independent clinical sign-off |
|---|---|---|
| `neck-ease-v1.0` | Sources, wording, recognition boundary, and tests reviewed in-repository | Not recorded for this beta |

Independent professional review is welcome as later content governance, but it is not required to build, test, or contribute to the current open-source beta.

欢迎后续将独立专业审校纳入内容治理，但它不是构建、测试或参与当前开源 Beta 的前置条件。

## Change governance / 变更规则

A movement-content change must include:

- the user benefit and intended scope;
- an authoritative source or relevant review;
- updated instructions, dose, and recognition-boundary text;
- deterministic tests and real-camera checks when recognition changes;
- a routine-version bump if saved history could be interpreted differently;
- an entry in `CHANGELOG.md`.

动作内容变更必须说明用户收益与范围，提供权威资料或相关综述，同步动作口令、次数和识别边界，补充相应测试；如果历史记录的解释发生变化，还必须升级内容版本并更新变更记录。
