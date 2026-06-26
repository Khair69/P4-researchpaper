# On-Stage Script + Cheat Sheet — Live P4 Firewall Demo
Arabic lines = what you SAY to the audience. [ACTION] = what you DO. Commands are exact.
Total time on stage: ~3 minutes. Rehearse it 3x so you never look at this on the day.

================================================================
BEFORE YOU WALK UP (pre-flight checklist)
================================================================
[ ] Server on, Wi-Fi up, you can SSH in.
[ ] NICs prepped (Phase 5) — both enp3s0 and enx9c69d33a9f57 show PROMISC,UP,LOWER_UP.
[ ] simple_switch running in tmux (Phase 6). 
[ ] Laptop A = 10.0.0.1, Laptop B = 10.0.0.2 (ipconfig confirms), Laptop B firewall set
    to Private / ICMP allowed.
[ ] A quick test ping A->B already worked once today.
[ ] Projector mirrors Laptop A. Two windows visible: LEFT = ping, RIGHT = SSH/CLI.
[ ] Terminal font BIG (Ctrl + mouse-wheel, or increase font size) — readable from the back.
[ ] BACKUP VIDEO of a clean run open in a tab, just in case.
[ ] The old switch on the table as a prop.

================================================================
THE SCRIPT
================================================================

--- 0. The hook (hold up the old switch) ---
«هذا مبدّل شبكة تقليدي. طريقة معالجته للحزم محفورة في الشريحة منذ التصنيع، ولا أستطيع
تغييرها مهما فعلت. هذه بالضبط هي المشكلة التي تعالجها لغة P4.»
[ACTION] put the old switch down, point to the server.
«اليوم لن أستخدم هذا المبدّل. سأحوّل حاسوباً عادياً إلى مبدّل قابل للبرمجة، ثم أبرمجه أمامكم.»

--- 1. Show it forwards (the baseline) ---
[ACTION] On Laptop A, start the ping (LEFT window):
    ping -t 10.0.0.2
«هذان حاسوبان حقيقيان، متّصلان عبر الخادم الذي يشغّل برنامج P4 كتبتُه بنفسي. الحزم تمرّ
وتصل — انظروا إلى الردود.»
[WAIT for a few replies to scroll.]

--- 2. Program a firewall rule, live ---
[ACTION] In the RIGHT window (CLI already open), type and run:
    table_add MyIngress.acl MyIngress.drop 10.0.0.2&&&0xffffffff => 1
«الآن أُدخل قاعدة واحدة إلى مستوى البيانات: أيّ حزمة وجهتها 10.0.0.2 — احذفها.»
[POINT at the LEFT window as replies turn into "Request timed out".]
«توقفت الردود فوراً. المبدّل نفسه يُسقط الحزم الآن — بسبب سطر برمجي كتبته للتوّ. بلا إعادة
تشغيل، وبلا أيّ جهاز جديد.»

--- 3. Remove it, traffic returns ---
[ACTION] In the RIGHT window:
    table_clear MyIngress.acl
«أحذف القاعدة...»
[POINT at LEFT window as replies resume.]
«وعادت الحركة. هذا هو مستوى البيانات القابل للبرمجة: أتحكّم بكيفية تعامل الشبكة مع الحزم،
لحظياً، بالكود.»

--- 4. The closing line ---
«المبدّل التقليدي في يدي لا يستطيع فعل هذا — منطقه مجمّد في السيليكون. لغة P4 حوّلت حاسوباً
عادياً إلى مبدّل أبرمجه كما أبرمج بقية طبقات نظامي. هذا جوهر بحثي.»

(OPTIONAL — if you also set up the advanced demo, add:)
«وأكثر من ذلك: يستطيع المبدّل أن يتذكّر ويقيس. شاهدوا — »
[ACTION] start ping; in CLI read counters climbing:
    counter_read MyIngress.port_pkts 0
«إنه يقيس حركته بنفسه، في الزمن الحقيقي، دون أيّ حزم قياس إضافية — هذا هو القياس الداخلي.»
[after ~20 packets the ping self-blocks]
«ولم آمره بالحجب — عدّ الحزم وقرّر بنفسه. المبدّل التقليدي بلا ذاكرة بين الحزم؛ لا يقدر على هذا.»
    register_write MyIngress.fw_count 0 0
«أمسح ذاكرته، فتعود الحركة.»

================================================================
ANTICIPATED QUESTIONS (have these ready)
================================================================
Q: "Why not run it on the real switch?"
   «لأن شريحته ثابتة الوظيفة — منطقها غير قابل للتعديل، وهذه هي المشكلة التي تحلّها P4
   بالانتقال إلى أهداف قابلة للبرمجة. هذا الحاسوب أحد تلك الأهداف (محاكي BMv2).»
Q: "Is this real hardware or a simulation?"
   «الحواسيب والكابلات حقيقية، والحزم حقيقية. المبدّل نفسه برمجي (BMv2) — وهو الهدف الرسمي
   لتطوير P4 واختباره. على شرائح مثل Tofino يعمل المنطق ذاته بسرعة التيرابت/ث.»
Q: "How fast is it?"
   «BMv2 محاكٍ برمجي للتحقق من صحة المنطق، لا للأداء؛ الأداء الفائق يأتي من العتاد المخصص.»
Q: "What is this used for in industry?"
   «موازنة الحمل، الجدران النارية، التخفيف من DDoS، والقياس — في Azure وMeta وGoogle.»

================================================================
ONE-PAGE CHEAT SHEET (print this; commands only)
================================================================
# --- before audience, on the server ---
PREP NICS:
  sudo ip addr flush dev enp3s0; sudo ip addr flush dev enx9c69d33a9f57
  sudo ip link set enp3s0 up promisc on; sudo ip link set enx9c69d33a9f57 up promisc on
START SWITCH (tmux):
  sudo docker run --rm -it --privileged --network host -v "$PWD":/work -w /work \
    p4lang/behavioral-model simple_switch -i 0@enp3s0 -i 1@enx9c69d33a9f57 \
    bridge_firewall.json --thrift-port 9090
OPEN CLI (2nd terminal):
  sudo docker run --rm -it --network host p4lang/behavioral-model \
    simple_switch_CLI --thrift-port 9090

# --- on Laptop A ---
  ping -t 10.0.0.2

# --- live, in the CLI ---
BLOCK:    table_add MyIngress.acl MyIngress.drop 10.0.0.2&&&0xffffffff => 1
UNBLOCK:  table_clear MyIngress.acl

# --- advanced program (stateful_firewall.json) extras ---
TELEMETRY:  counter_read MyIngress.port_pkts 0
            counter_read MyIngress.port_pkts 1
SEE STATE:  register_read  MyIngress.fw_count 0
RESET:      register_write MyIngress.fw_count 0 0

# --- recover from trouble ---
RESTART SWITCH: Ctrl-C in tmux, re-run START SWITCH
KILL STUCK:     sudo pkill -f simple_switch
REATTACH TMUX:  tmux attach -t p4
