# 찬찬배틀 — 인수인계 노트 (다른 Claude 세션이 바로 이어서 작업하기 위한 문서)

> **작업이 끝날 때마다 이 파일의 "작업 기록"과 관련 섹션을 갱신하고 커밋할 것.**

## 사용자와 일하는 규칙
- 사용자에게 보이는 글은 **전부 한국어** (진행 메모, 마지막 답변 포함). 영어로 쓰면 싫어함.
- 사용자는 빠른 반영을 원함: 기능 만들기 → 브라우저로 확인 → `main`에 커밋 + 푸시 (GitHub Pages 자동 배포). "올려줘" = 푸시.
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- 사용자 비밀번호 입력, 외부 서비스 계정 생성 금지 (테스트 계정도 X). Supabase 대시보드는 사용자가 로그인해 둔 브라우저 탭에서 SQL Editor로 작업.
- service_role 키는 절대 쓰지 않음. 게임에는 anon(공개) 키만.
- 파일 다운로드는 먼저 허락받기.

## 프로젝트 개요
- 종이(페이퍼) 스타일 브라우저 FPS. **단일 파일 `index.html`** (Three.js r160, `lib/three.min.js`), ~5,500줄.
- 배포: GitHub Pages — https://woochy338.github.io/chanchan-fps/ (repo `WOOCHY338/chanchan-fps`, 브랜치 `main`)
- 로컬 확인: `node server.js` (포트 3000) / `.claude/launch.json`의 `chanchan-server`
- 온라인: PeerJS P2P (호스트 권한형). 계정·경쟁전·상점: Supabase (`supabase.sql`, `supabase_shop.sql`)
- Supabase 프로젝트: chanchan-battle (org moneyroad, eu-west-1), URL `https://mqdzetyhwltrjvwhkpty.supabase.co`

## 코드 지도 (index.html, 키워드로 검색)
- 렌더러/씬: `// ── THREE.JS SETUP ──`, 뷰모델은 별도 `vmScene`/`vmCamera`. 헬퍼 `inked`, `part`, `tube`, `prof`, `rbox`.
- 총: `GUNS`(rifle=A-K, shotgun=더블배럴, sniper=저격총), A-K 모델 `const gun`, 저격총 `srGun`, 산탄총 `sg`. B키 = 주무기 선택.
- 칼: `sampleKnife`, `knifeState`, 카람빗 찌르기(발로란트 챔스 2021 참고), `KNIFE_SKINS`.
- 맵: `MAPS` (arena / bomb), `BOMB_SCALE = 1.4`, `BOMB_SITES`, `BOMB_SPAWNS`, 미니맵 `drawMinimap`.
- 네트워크: `createHostRoom`, `netSend`, 메시지 create/join/team/mode/start/state/shot/anim/hit/chat/talk. 일반방 코드 PB01–PB12.
- 보이스: PeerJS 미디어 풀메시, V 팀 / U 전체.
- 경쟁전: `rankedMatch`, `startQueueScreen`, `ranked_rooms` 테이블, 티어 `divName` (스톤1 → 챌린저2, 챔피언 = 상위 5명).
- 상점: `AK_SKINS`, `RARITY`, `GEM_LOOKS`/`gemTexture`(케이스 하드닝 텍스처), `applyAkSkin`, `openCase`, `buyItem`, `ITEM_PRICE`, `refreshShop`.
- 나만의 스킨: `custom`, `CUSTOM_GUNS`(rifle·sniper), `applyCustom`, `applySniperSkin`, `setCustomImage`, `renderCustomEditor`. 디자인은 **계정에 저장** (`custom_skins` 테이블, 본인만 읽기 / `save_custom_skin(gun, design)` RPC, 0.6초 디바운스) → 어느 기기에서 로그인해도 같고 남은 못 봄. `loadCustom()`이 로그인 시 불러오고 로그아웃 시 초기화. 구매는 서버(`buy_item('custom')`, 100크레딧, skins_owned.skin='custom').
- 스킨 UV: `skinParts()`가 총 옆면 기준 두 번째 UV(`uvSkin`)를 만들어서 텍스처 스킨이 총 전체에 이어지게 함 (u: 개머리판 0 → 총구 1).
- 설정: `#settings-panel` 하나를 메인 화면 "설정" 페이지(`#settings-home`, class `in-page`)와 게임 중 ESC(떠 있는 패널) 사이에서 옮겨 씀. 값은 localStorage `settings`(JSON)에 저장 (`SAVED_SETTINGS`).
- 그래픽: `GFX_TIERS` (high/mid/low = 그림자 품질), `setQuality`, `setTier`, `gfxFrame`(FPS 측정 + 자동 조절). **해상도는 절대 낮추지 않음** (사용자 친구들이 싫어함). 안티앨리어싱은 `gfxAA`(새로고침 후 적용).
- 메인 루프: `function animate()`.

## Supabase 서버 함수 (supabase_shop.sql)
- 크레딧·뽑기·랭크 변경은 전부 security definer RPC에서만: `report_result`, `shop_status`, `claim_reward('playtime'|'ranked3'|'win1')`, `open_case`, `equip_skin`, `buy_item('karambit'|'custom')`. 나만의 스킨 디자인: `save_custom_skin` + 테이블 `custom_skins`(PK user_id+gun, design jsonb ≤ 1MB).
- `_my_profile`(내부용, 한국 자정에 일일 카운터 초기화), `admin_give_credits`(SQL Editor 전용).
- 슈퍼 계정: `profiles.super = true` → 모든 스킨/칼/나만의 스킨 보유 취급. `square15678`(사용자 본인 계정)이 슈퍼, 999,999 크레딧.
- SQL을 바꾸면 supabase_shop.sql 끝에 추가 + 대시보드 SQL Editor에서 실행 (Monaco: `monaco.editor.getModels()[0].setValue(sql)` 후 Run 버튼).

## 테스트 요령
- 브라우저 패널이 숨겨져 있으면 rAF가 멈춤 → 게임 함수(`update`, `renderer.render`)를 직접 호출하고 `renderer.domElement.toDataURL()`을 img로 띄워 스크린샷.
- 로그인이 필요한 흐름은 `account.profile`과 `sb.rpc`를 가짜로 바꿔서 확인.
- Windows 경로가 길어서 git은 `git -c core.longpaths=true ...`.

## 작업 기록 (최신이 위)
- 2026-11-03: 나만의 스킨 디자인을 브라우저(localStorage) 대신 계정(Supabase `custom_skins`)에 저장하도록 변경.
- 2026-11-03: 블루젬 A-K를 실제 CS2 케이스 하드닝 #661처럼 다시 만듦 (총 전체에 이어지는 패턴, 광택 금속). 레드젬도 같은 방식.
  - 나만의 스킨 (A-K·저격총, 100크레딧): 부위별 색상 조정 또는 PNG 그림 + 색조/채도/밝기 조절.
  - ESC 설정을 메인 화면 "설정" 페이지로 옮기고 기기에 저장. 그래픽 설정(자동 60프레임 방어/높음/중간/낮음, 안티앨리어싱, FPS 표시) 추가.
- 2026-11-02: 카람빗 50크레딧 상점 판매, 슈퍼 계정, 충전 버튼 "충전은 아직 없어요".
- 그 전: 상점(찬크레딧, 노이펙트 상자, 퀘스트), 경쟁전(매칭 큐, 1v1/2v2/5v5), 폭탄전 맵(A/B 사이트, 1.4배), 산탄총·저격총, 인벤토리, 채팅·보이스, 발로란트식 메인 화면, 앉기(Ctrl/C), 전체화면 키 잠금(1+0으로 나가기).

## 아직 안 한 것 / 아이디어
- 다른 플레이어에게 내 A-K 스킨이 안 보임 (스킨은 내 화면에서만). 나만의 스킨은 의도적으로 본인만.
- PeerJS가 막힌 네트워크에서는 매칭이 안 될 수 있음 → Supabase Realtime으로 시그널링 옮기는 방안.
- 산탄총·A-K의 다리 데미지 따로 없음.
