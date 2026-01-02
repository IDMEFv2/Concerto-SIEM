#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from elastalert.alerts import Alerter, BasicMatchString
import json
import datetime
import os
import yaml
from kafka import KafkaProducer
import uuid


class ConcertoAlerter(Alerter):
    def prepare_idmef(self, conf, name, descr, filename, idmef, match):
        ret = {
            "Analyzer": {
                "Category": ["SIEM"],
                "Data": ["Alert"],
                "Method": ["Correaltion"],
                "Type": "Combined",
            },
            "ID": str(uuid.uuid4()),
            "Description": name,
            "CreateTime": str(datetime.datetime.now(datetime.UTC).strftime('%Y-%m-%dT%H:%M:%S.%fZ')),
            "Note": descr,
            "Ref": [os.path.basename(filename)],
            "Version": match["Version"],
            "CorrelID": [match['ID']],
            "Attachment": [ {
                "Content": json.dumps(match),
                "ContentType": "application/json",
                "Name": "RawAlert"
                } ]
        }
        for i in ['IP', 'Hostname', 'Location', 'Model', 'Name', 'UnLocation']:
            if i in conf:
                ret["Analyzer"][i] = conf[i]
        for i in ["Source", "Target", "Vector"]:
            if i in match:
                ret[i] = match[i]
        if "Category" in idmef and type(idmef["Category"]) == type([]):
            ret["Category"] = idmef["Category"]
        if "Priority" in idmef and idmef["Priority"] in ["Unknown", "Info", "Low", "Medium", "High"]:
            ret["Priority"] = idmef["Priority"]
        return ret

    def alert(self, matches):
        with open("/opt/kafka.yaml", "r+") as f:
            conf = yaml.safe_load(f.read())
        k = KafkaProducer(bootstrap_servers=[conf['bootstrapserver']])
        
        for match in matches:
            idmef = self.prepare_idmef(conf, self.rule['name'], self.rule['description'], self.rule['rule_file'], self.rule['idmefv2'], match)
            k.send("my_processed", json.dumps(idmef).encode('utf-8'))

    def get_info(self):
        return {
            'type': 'Concerto Alerter',
        }
