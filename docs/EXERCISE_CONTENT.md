# MellowDesk Exercise Content / 小桌伴动作内容

Routine version / 内容版本: `neck-ease-v1.0`

App release / App 版本: `v0.1.0-beta.7`

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

## Pelvic-floor follow-along / 提肛跟练

Routine version / 内容版本: `pelvic-floor-v1.0`

**English:** A two-minute paced pelvic-floor (Kegel) follow-along, enabled by default, included in the regular reminder rotation, and available directly from the menu bar. It can be disabled in Settings. It is a visual pacing guide only: no camera, no sensor, and no movement measurement. Finishing the full guide records one local completion for history and statistics; skipping records nothing. Twelve bars arranged as a clock face contract together toward the center while lifting, stay in while holding, and return outward while releasing; a dashed circle marks the relaxed position.

**中文：**一段两分钟的提肛跟练，默认开启并进入常规提醒轮换，也可从菜单栏直接开始或在设置中关闭。它只是节奏引导：不用摄像头、不使用传感器、不做识别、不计次判定。完整练完后会写入一条本地完成记录，供完成历史和统计使用；跳过不会记录。12 根竖线排成表盘形状：收提时一起向圆心收缩，保持时停在内侧，放松时还原到外侧；虚线圆环标出放松位置。

| Segment | UI name | Tempo | Product dose |
|---|---|---|---:|
| 1 | 慢速提肛 | 3 s lift · 2 s hold · 3 s release · 2 s rest | 3 lifts / 30 s |
| 2 | 快速提肛 | 1 s lift · 1 s release | 15 lifts / 30 s |
| 3 | 快快慢 | short · short · long, then a full rest beat (a *We Will Rock You* style pattern) | 15 lifts / 30 s |
| 4 | 快提慢放 | fast lift · 1.5 s hold · 3 s release · 1 s rest | 5 lifts / 30 s |

The tempo pattern in segment 3 is only a familiar rhythmic feel; no music, audio, or lyrics from any recording are used or reproduced.

第三段只是借用一种熟悉的节奏感，不使用也不复制任何录音、音频或歌词。

Breathe normally throughout. Do not hold your breath or squeeze the abdomen, buttocks, or thighs at the same time. Stop and consult a professional if there is pain, marked discomfort, or worsening of an existing symptom.

全程自然呼吸，不憋气，也不要同时收紧腹部、臀部或大腿。出现疼痛、明显不适或原有症状加重请停止，并咨询专业人士。

Slow-and-fast contraction sets are a common shape for general pelvic-floor practice, and the doses above are a product pacing choice, not a treatment prescription or an individualized program. MellowDesk claims no therapeutic effect for this practice and does not evaluate whether any contraction happened.

慢速与快速交替是一般盆底练习的常见形式，上面的次数只是产品节奏安排，不是治疗处方或个体化方案。小桌伴不宣称这项练习具有治疗作用，也不判断用户是否真的完成了收提。

## Content status / 内容状态

| Version | Maintainer review | Independent clinical sign-off |
|---|---|---|
| `neck-ease-v1.0` | Sources, wording, recognition boundary, and tests reviewed in-repository | Not recorded for this beta |
| `pelvic-floor-v1.0` | Wording, tempo, safety boundary, and deterministic tests reviewed in-repository | Not recorded for this beta |

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
