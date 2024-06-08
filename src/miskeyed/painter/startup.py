"""
As substance painter does not ship with a way to package plugins to share we are using pip as the method to share.
"""
import substance_painter as sp
import substance_painter_plugins

import logging

class CustomHandler(logging.Handler):
    def emit(self, record):
        log_entry = self.format(record)
        if record.levelno == logging.INFO:
            sp.logging.log(sp.logging.INFO, record.name, log_entry)
        elif record.levelno == logging.WARNING:
            sp.logging.log(sp.logging.WARNING, record.name, log_entry)
        elif record.levelno == logging.ERROR:
            sp.logging.log(sp.logging.ERROR, record.name, log_entry)
        else:
            sp.logging.log(sp.logging.INFO, record.name, log_entry)

def setup():
    log = logging.getLogger('miskeyed')
    custom_handler = CustomHandler()
    custom_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
    log.addHandler(custom_handler)
    log.setLevel(logging.INFO)

    log.info("Welcome to Miskeyed Substance Painter Toolkit")


def teardown():
    log.info("Bye bye :(")