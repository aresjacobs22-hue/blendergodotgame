# Lays the rendered shots out as one labelled contact sheet per monster.
#   python3 sheets.py <out dir>
import json, os, subprocess, sys

out = sys.argv[1]
P = f"{out}/png"


def col(k, label, sub, main=None, small=None):
    return {"label": label, "sub": sub, "main": main or f"{P}/{k}_front.png",
            "small": small or [f"{P}/{k}_side.png", f"{P}/{k}_head.png"]}


def statue(k, label, sub):
    return col(k, label, sub, f"{P}/{k}@4_front.png", [f"{P}/{k}@2_front.png", f"{P}/{k}@4_head.png"])


sheets = [
    {"out": f"{out}/sheets/1_Hollow.png", "title": "NIGHT 1 · THE HOLLOW  —  pick A, B or C", "mood": "house", "cols": [
        col("HollowA", "A · THE SKULL", "starved black body, deer skull + antlers, pinpoint eyes"),
        col("HollowB", "B · THE GRIN", "a tall shadow: only its glowing smile + eyes show"),
        col("HollowC", "C · THE WIDOW", "black dress, long hair, cracked porcelain mask")]},
    {"out": f"{out}/sheets/2_Crawler.png", "title": "NIGHT 2 · THE CRAWLER  —  pick A, B or C", "mood": "ward", "cols": [
        col("CrawlerA", "A · THE SPIDER", "8 long legs, head hangs upside down, 6 red eyes"),
        col("CrawlerB", "B · THE PATIENT", "bent over backwards, 4 extra arms, hair dragging"),
        col("CrawlerC", "C · THE HANDS", "walks on 8 human hands, face = round mouth of teeth")]},
    {"out": f"{out}/sheets/3_Listener.png", "title": "NIGHT 3 · THE LISTENER  —  pick A, B or C", "mood": "sewer", "cols": [
        col("ListenerA", "A · THE DROWNED", "pale + swollen, empty eye holes, split jaw hanging"),
        col("ListenerB", "B · THE LURE", "blind fish head; you see its glowing bulb first"),
        col("ListenerC", "C · THE SPLIT", "holds its blind head, which splits open when it hears")]},
    {"out": f"{out}/sheets/4_Statue.png", "title": "NIGHT 4 · THE STATUE  —  pick A, B or C   (big = lunge pose, small = weeping pose + face)", "mood": "atrium", "cols": [
        statue("StatueA", "A · THE MOURNER", "hooded robes, red pinpoint eyes in the dark of the hood"),
        statue("StatueB", "B · THE MANNEQUIN", "jointed marble doll, red light glows through its cracked face"),
        statue("StatueC", "C · THE SAINT", "crown of spikes, 3 screaming faces (one always faces you)")]},
    {"out": f"{out}/sheets/5_Amalgam.png", "title": "NIGHT 5 · THE AMALGAM  —  pick A, B or C", "mood": "void", "cols": [
        col("AmalgamA", "A · THE MASS", "hulking heap of bodies, 3 heads, glowing heart in its ribs"),
        col("AmalgamB", "B · THE TOWER", "bodies stacked on bodies, arms reaching out everywhere"),
        col("AmalgamC", "C · THE MAW", "its whole front is one mouth, heart glowing in its throat")]},
]
json.dump(sheets, open(f"{out}/sheets.json", "w"))
subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "sheet.py"), f"{out}/sheets.json"], check=True)
