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
- 네트워크: `createHostRoom`, `netSend`, 직접 P2P가 4초 안에 안 열리면 Supabase Realtime 중계(`relayLink`/`hostRelay`/`joinRelay`, 채널 `cc-room-코드`)로 자동 전환. 일반방 목록은 P2P 확인 + `cc-lobby` 브로드캐스트(`scanLobby`; Presence는 이 프로젝트에서 응답 없음). PeerJS 무료 TURN은 죽어 있음. 메시지 create/join/team/mode/start/state/shot/anim/hit/chat/talk. 일반방 코드 PB01–PB12.
- 보이스: PeerJS 미디어 풀메시, V 팀 / U 전체.
- 경쟁전: `rankedMatch`, `startQueueScreen`, `ranked_rooms` 테이블, 티어 `divName` (스톤1 → 챌린저2, 챔피언 = 상위 5명).
- 상점: `AK_SKINS`, `RARITY`, `GEM_LOOKS`/`gemTexture`(케이스 하드닝 텍스처), `applyAkSkin`, `openCase`, `buyItem`, `ITEM_PRICE`, `refreshShop`.
- 나만의 스킨: `custom[g]` = { metal, wood, mag 색, on(저격총 장착), parts(스티커 붙는 부위), stickers[{img, c(총 공간 표면 중심), d(붙인 방향), w(폭), a(세로/가로), r(회전), hue, sat, bright}], slots[2] }. 정점마다 총 공간 위치·법선(`gunPos`/`gunNor` 속성, `skinParts`에서 계산) → `stickerMat` 셰이더가 스티커마다 행렬(`uStk`)로 투영, 그림은 아틀라스(4×2칸) 한 장(`customGpu`/`paintCustom`). 편집기 `ce`(yaw/pitch/zoom, 정사영, 전용 렌더러), `ceSurface`(레이캐스트로 표면 찾기), `ceShape`/`ceHit`. 계정 저장(`custom_skins`, `save_custom_skin` RPC, 0.6초 디바운스, 4MB 제한). 구매는 `buy_item('custom')`, 100크레딧.
- 스킨 UV: `skinParts()`가 총 옆면 기준 두 번째 UV(`uvSkin`)를 만들어서 텍스처 스킨이 총 전체에 이어지게 함 (u: 개머리판 0 → 총구 1).
- 설정: `#settings-panel` 하나를 메인 화면 "설정" 페이지(`#settings-home`, class `in-page`)와 게임 중 ESC(떠 있는 패널) 사이에서 옮겨 씀. 값은 localStorage `settings`(JSON)에 저장 (`SAVED_SETTINGS`).
- 그래픽: `GFX_TIERS` (high/mid/low = 그림자 품질), `setQuality`, `setTier`, `gfxFrame`(FPS 측정 + 자동 조절). **해상도는 절대 낮추지 않음** (사용자 친구들이 싫어함). 안티앨리어싱은 `gfxAA`(새로고침 후 적용).
- 메인 루프: `function animate()`.

## Supabase 서버 함수 (supabase_shop.sql)
- 크레딧·뽑기·랭크 변경은 전부 security definer RPC에서만: `report_result`, `shop_status`, `claim_reward('playtime'|'ranked3'|'win1')`, `open_case`, `equip_skin`, `buy_item('karambit'|'custom')`. 나만의 스킨 디자인: `save_custom_skin` + 테이블 `custom_skins`(PK user_id+gun, design jsonb ≤ 1MB).
- `owner_give_credits(nick, amount)`: 주인 계정(square15678, id `b6cb9762-1599-48c7-a940-a074c5e0bf89`)만 호출 가능. 상점 화면 위 "관리자 · 찬크레딧 넣기" 칸(`renderOwnerTools`).
- `_my_profile`(내부용, 한국 자정에 일일 카운터 초기화), `admin_give_credits`(SQL Editor 전용).
- 슈퍼 계정: `profiles.super = true` → 모든 스킨/칼/나만의 스킨 보유 취급. `square15678`(사용자 본인 계정)이 슈퍼, 999,999 크레딧.
- SQL을 바꾸면 supabase_shop.sql 끝에 추가 + 대시보드 SQL Editor에서 실행 (Monaco: `monaco.editor.getModels()[0].setValue(sql)` 후 Run 버튼).

## 테스트 요령
- 브라우저 패널이 숨겨져 있으면 rAF가 멈춤 → 게임 함수(`update`, `renderer.render`)를 직접 호출하고 `renderer.domElement.toDataURL()`을 img로 띄워 스크린샷.
- 로그인이 필요한 흐름은 `account.profile`과 `sb.rpc`를 가짜로 바꿔서 확인.
- Windows 경로가 길어서 git은 `git -c core.longpaths=true ...`.

## 작업 기록 (최신이 위)
- 2026-11-07: 마이크 처음부터 켜짐(첫 클릭/키 입력 때 자동 `toggleMic`, 말하기는 여전히 V/U). 총(주무기) 선택은 온라인에서 라운드 시작 전 5초(`RULES.prestart` 3→5)에만: 그때 선택 메뉴 자동으로 열리고 카운트다운, 라운드 중엔 B 막힘(`canSwapGun`, 데스매치는 죽어 있을 때도 가능).
- 2026-11-05: 배치고사 3판(`profiles.placement`/`placement_wins`, `report_result`에서 처리: 0승 스톤2 · 1승 브론즈2 · 2승 실버2 · 3승 골드2, 배치 중 점수 변동 없음). 처음 SQL 실행 때 스톤(division ≤ 1)만 배치 3판, 새 계정도 배치부터. **아직 Supabase에 SQL 안 넣음** (supabase_shop.sql 끝의 배치고사 + open_axe_case).
- 2026-11-05: 도끼(`axeKnife`, 발로란트 네오프런티어 도끼 모양: 검은 머리 + 초록 네온 날) + 모션(`AXE_ANIMS`: 프라임 좌클릭 가로 베기 lightA/lightB, 우클릭 내려찍기 heavy, 스왑 draw, 자세히보기 inspect — 유튜브 L1BK0e2Zq00 자막 기준). 노이펙트 도끼 상자(`open_axe_case`, 50, 같은 확률, 스킨 `a_<id>`, 장착 `axFinish`/`applyAxFinish`).
- 2026-11-05: 데스매치(`type: 'dm'`, `DM` 설정: 30킬/5분/1.5초 부활) — 개인전(시작 때 모두 red 팀으로 바꿔 적으로 보이게), 부활 위치는 `DM_POINTS`(아레나 빈 곳 격자) 중 살아있는 사람과 가장 먼 곳, 메시지 `respawn`/`dmscore`, 끝나면 `end.dm`에 킬 수. 산탄총 동그란 조준점(`#crosshair.round`).
- 2026-11-05: 멀티 지연 줄임 — 게스트마다 두 번째 PeerJS 연결(`metadata.fast`, `reliable:false` = 순서 없음)로 state/snap 전송(`netSendFast`, 호스트 `setFast`/`sendFast`), 순서 뒤바뀐 건 버림(`me.lastTs`, `net.lastHt`). 전송·호스트 틱 20→30Hz, INTERP 0.05, 중계 플러시 33ms. 모바일: 시작할 때 PC/모바일 선택, 터치 버튼 편집(`touchLayout`, 조이스틱 `touchStick`), 조준/앉기 토글(`touchToggle`), 모바일 전용 조준 보정(`AIM_ASSIST`: 5° 안 감속 35%, 조작 중일 때만 초당 9° 끌림, 벽 뒤 X). 모바일은 포인터 락 안 씀(터치 노트북에서 터치가 캔버스로만 가서 조이스틱이 죽었음).
- 2026-11-04: 멀티 부드럽게(전송 주기 20Hz 그대로): 보내는 쪽 시계(`ts`) → 방장이 플레이어별 '찍힌 시각' `at` + 스냅샷 `ht` 붙임 → 받는 쪽은 도착 시각이 아니라 찍힌 시각으로 타임라인 배치(`net.hOff` 최소 지연 필터), 같은 상태 중복은 버림, 지연 버퍼 = 전송 간격 + 도착 나이(`r.ageAvg/ageDev`), Catmull-Rom 곡선 보간 + 25ms 화면 보정(큰 순간이동은 즉시). 시뮬(나쁜 와이파이·30fps): 흔들림 182→14, 실제 지연 326→262ms. 시뮬 스크립트는 세션 스크래치에만 있음.
- 2026-11-04: 설정창에서 칼(스킨) 선택 숨김 — 칼은 인벤토리에서만 바꿈 (`#knife-select`는 숨긴 채로 남아 적용·저장 담당).
- 2026-11-04: 상점 관리자 칸(본인 계정에만 보임)의 '100 찬크레딧 = 500원' 문구 삭제.
- 2026-11-04: 확정 카람빗 판매 종료 → 노이펙트 카람빗 상자(50, `open_knife_case`, 스킨 id `k_<스킨>`, 장착은 기기 저장 `kbFinish`/`applyKbFinish`). 케이스 하드닝 텍스처를 픽셀 노이즈 방식으로 새로 만듦(`gemTexture`, `GEM_LOOKS.ramp`). 멀티: 플레이어별 지터 버퍼(`r.delay`), 늦은 패킷 100ms 예측, 내 화면에서 치명타면 바로 쓰러짐(`u.predT`, 호스트가 안 받아주면 0.8초 뒤 복구).
- 2026-11-04: 캐릭터에 안 보이는 판정 박스(`hitboxMat`, 머리/몸통/다리) — 종이 몸이 옆에서 14cm라 맞는 총알이 빗나갔음. 나만의 스킨 미리보기를 게임 렌더러 하나로 그림(두 번째 WebGL 컨텍스트 제거, 편집기 조명은 장면에 고정). WebGL 컨텍스트 끊기면 안내 후 새로고침. 약한 GPU(Intel 등)는 안티앨리어싱 기본 끔(`weakGpu`). 학교 PC = Intel UHD. 관리자 찬크레딧 넣기 SQL 적용 완료.
- 2026-11-04: 학교 와이파이처럼 PC끼리 직접 연결이 막힌 곳에서도 방 목록·참가·경쟁전이 되도록 Supabase 중계 추가. 경쟁전 시간은 Supabase 서버 시계 기준(`boardTime`). 화면 비율(기본/4:3 스트레치/4:3 블랙바).
- 2026-11-03: 나만의 스킨 = 총 표면에 붙는 스티커(카스2식). 편집기에서 총을 돌려가며(빈 곳 드래그, 게임 시점/왼쪽/오른쪽/위 버튼, 휠 확대) 원하는 면에 붙임. 저장 슬롯 2개(계정 저장, design.slots). 서버 크기 제한 4MB.
- 2026-11-03: 스티커를 게임 카메라 시점에서 투영(원근 정확: 정점마다 clip 좌표 `decalH` 속성 + `stickerMat` 셰이더에서 나눗셈). 편집 미리보기 = 게임 화면에 보이는 부분 그대로(같은 카메라, `setViewOffset`로 자름), 팔은 흐리게 표시. 플레이어 반대쪽 면/화면 밖은 단색.
- 2026-11-03: 나만의 스킨을 카스2/카트 스티커 방식으로: 사진 스티커 여러 장(최대 8), 미리보기에서 드래그 이동·■ 크기·● 회전·휠. 왼쪽 면(게임에서 보이는 쪽)도 글자가 바로 읽히게 거울 처리. 미리보기는 전용 렌더러 + 정사영 카메라라 화면 좌표 = 총 옆면 좌표.
- 2026-11-03: 나만의 스킨 사진을 원하는 부분에만: 넣을 부위(금속/나무·몸통/탄창) 선택 + 좌우·위아래·크기 조절, 사진 비율 유지. 미리보기는 실제 3D 총을 옆에서 렌더링(`drawCustomPreview`).
- 2026-11-03: 나만의 스킨 디자인을 브라우저(localStorage) 대신 계정(Supabase `custom_skins`)에 저장하도록 변경.
- 2026-11-03: 블루젬 A-K를 실제 CS2 케이스 하드닝 #661처럼 다시 만듦 (총 전체에 이어지는 패턴, 광택 금속). 레드젬도 같은 방식.
  - 나만의 스킨 (A-K·저격총, 100크레딧): 부위별 색상 조정 또는 PNG 그림 + 색조/채도/밝기 조절.
  - ESC 설정을 메인 화면 "설정" 페이지로 옮기고 기기에 저장. 그래픽 설정(자동 60프레임 방어/높음/중간/낮음, 안티앨리어싱, FPS 표시) 추가.
- 2026-11-02: 카람빗 50크레딧 상점 판매, 슈퍼 계정, 충전 버튼 "충전은 아직 없어요".
- 그 전: 상점(찬크레딧, 노이펙트 상자, 퀘스트), 경쟁전(매칭 큐, 1v1/2v2/5v5), 폭탄전 맵(A/B 사이트, 1.4배), 산탄총·저격총, 인벤토리, 채팅·보이스, 발로란트식 메인 화면, 앉기(Ctrl/C), 전체화면 키 잠금(1+0으로 나가기).

## 아직 안 한 것 / 아이디어
- 다른 플레이어에게 내 A-K 스킨이 안 보임 (스킨은 내 화면에서만). 나만의 스킨은 의도적으로 본인만.
- 중계로 들어온 사람과는 보이스가 안 될 수 있음 (보이스는 아직 P2P 전용).
- 산탄총·A-K의 다리 데미지 따로 없음.
