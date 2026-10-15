"""Isolated real-broker test for the native MQTT wire/session core."""
from pathlib import Path
import argparse, hashlib, json, socket, subprocess, time
p=argparse.ArgumentParser();p.add_argument('--broker',required=True);p.add_argument('--compiler',required=True);p.add_argument('--work',type=Path,required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
oracle=work/'mqtt-broker-oracle';subprocess.run([a.compiler,str(root/'tests/esp32/mqtt-broker-oracle.flex'),'-o',str(oracle)],check=True,cwd=root)
with socket.socket() as choose:choose.bind(('127.0.0.1',0));port=choose.getsockname()[1]
config=work/'mosquitto.conf';config.write_text(f'listener {port} 127.0.0.1\nallow_anonymous true\npersistence false\nmax_inflight_messages 2\nlog_type all\n')
report={'passed':False,'scope':'native Linux MQTT wire/session core; ESP32 transport not exercised','broker_sha256':hashlib.sha256(Path(a.broker).read_bytes()).hexdigest(),'port':port}
with (work/'broker.log').open('wb') as log:
    broker=subprocess.Popen([a.broker,'-c',str(config),'-v'],stdout=log,stderr=subprocess.STDOUT)
    try:
        deadline=time.monotonic()+5
        while True:
            if broker.poll() is not None:raise RuntimeError('broker exited; see broker.log')
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.1):break
            except OSError:
                if time.monotonic()>deadline:raise
                time.sleep(.02)
        run=subprocess.run([str(oracle),str(port)],capture_output=True,timeout=20)
        (work/'stdout.log').write_bytes(run.stdout);(work/'stderr.log').write_bytes(run.stderr)
        report['oracle_exit']=run.returncode;assert run.returncode==0,(run.returncode,run.stderr.decode(errors='replace'))
        assert b'PASS: native MQTT Mosquitto interoperability' in run.stdout
        text=(work/'broker.log').read_text();assert text.count(' as flexscript-native-oracle (')==2,text
        assert 'Received PINGREQ' in text and text.count('Received SUBSCRIBE')==2 and text.count('Received UNSUBSCRIBE')==2
        for qos in range(3):assert f'Received PUBLISH from flexscript-native-oracle (d0, q{qos},' in text
        assert text.count('Received PUBREC from flexscript-native-oracle')>=2 and text.count('Received PUBCOMP from flexscript-native-oracle')>=2
        report.update(passed=True,messages=4,outgoing_completed_qos=3,connections=2,session_present_on_reconnect=True,ping_response=True,subscriptions=2,unsubscriptions=2,tx_fragment_bound=17,rx_fragment_bound=31)
    finally:
        broker.terminate()
        try:broker.wait(timeout=3)
        except subprocess.TimeoutExpired:broker.kill();broker.wait()
        (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: native MQTT core / independent Mosquitto broker')
