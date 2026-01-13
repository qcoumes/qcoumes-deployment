eMushpedia Archives
===================

This app dump the whole content of https://emushpedia.miraheze.org everyday and make the dumps available to download on the web.

To run it you need to create a python3 virtual environnement named `venv` **in this directory** and install the package in `requirements.txt`:

```sh
python3 -m venv venv
souce venv/bin/activate
pip3 install -U pip wheel setuptools
pip3 install -r requirements.txt
deactivate
```

You then need to add the following line to your crontab (you can change when you want it to run):

```sh
6 0 * * * <path_to_this_directory>/dump.sh
```
