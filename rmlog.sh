E_NOARGS=3
if [ -z "$1" ]
then
  echo "Usage: "
  echo "  ./$(basename $0) \"added new guest account\" "
  echo
  exit $E_NOARGS
fi
sed -i "$1"'d' /root/.maintenance
exit 0
