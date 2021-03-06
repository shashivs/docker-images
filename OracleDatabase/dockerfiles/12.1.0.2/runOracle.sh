#!/bin/bash

########### SIGTERM handler ############
function _term() {
   echo "Stopping container."
   echo "SIGTERM received, shutting down database!"
   sqlplus / as sysdba <<EOF
   shutdown immediate;
EOF
   lsnrctl stop
}

########### SIGKILL handler ############
function _kill() {
   echo "SIGKILL received, shutting down database!"
   sqlplus / as sysdba <<EOF
   shutdown abort;
EOF
   lsnrctl stop
}

############# Create DB ################
function createDB {

   # Auto generate ORACLE PWD
   ORACLE_PWD=`openssl rand -base64 8`
   echo "ORACLE AUTO GENERATED PASSWORD FOR SYS, SYSTEM AND PDBAMIN: $ORACLE_PWD";

   cp $ORACLE_BASE/$CONFIG_RSP $ORACLE_BASE/dbca.rsp

   sed -i -e "s|###ORACLE_SID###|$ORACLE_SID|g" $ORACLE_BASE/dbca.rsp
   sed -i -e "s|###ORACLE_PDB###|$ORACLE_PDB|g" $ORACLE_BASE/dbca.rsp
   sed -i -e "s|###ORACLE_PWD###|$ORACLE_PWD|g" $ORACLE_BASE/dbca.rsp

   mkdir -p $ORACLE_HOME/network/admin
   echo "NAME.DIRECTORY_PATH= {TNSNAMES, EZCONNECT, HOSTNAME}" > $ORACLE_HOME/network/admin/sqlnet.ora

   # Listener.ora
   echo "LISTENER = 
  (DESCRIPTION_LIST = 
    (DESCRIPTION = 
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1)) 
      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521)) 
    ) 
  ) 

" > $ORACLE_HOME/network/admin/listener.ora

# Start LISTENER and run DBCA
   lsnrctl start &&
   dbca -silent -responseFile $ORACLE_BASE/dbca.rsp ||
    cat /opt/oracle/cfgtoollogs/dbca/$ORACLE_SID/$ORACLE_SID.log

   echo "$ORACLE_SID=localhost:1521/$ORACLE_SID" >> $ORACLE_HOME/network/admin/tnsnames.ora
   echo "$ORACLE_PDB= 
  (DESCRIPTION = 
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = $ORACLE_PDB)
    )
  )" >> /$ORACLE_HOME/network/admin/tnsnames.ora

   sqlplus / as sysdba << EOF
      ALTER PLUGGABLE DATABASE $ORACLE_PDB SAVE STATE;
EOF

  rm $ORACLE_BASE/dbca.rsp

}

############# Check DB ################
function checkDBExists {
   # No entry in oratab, DB doesn't exist yet
   if [ "`grep $ORACLE_SID /etc/oratab`" == "" ]; then
      echo 0;
   else
      echo 1;
   fi;
}

############# Start DB ################
function startDB {
   lsnrctl start
   sqlplus / as sysdba <<EOF
   startup;
EOF

}

############# MAIN ################

# Set SIGTERM handler
trap _term SIGTERM

# Set SIGKILL handler
trap _kill SIGKILL

# Default for ORACLE SID
if [ "$ORACLE_SID" == "" ]; then
   export ORACLE_SID=ORCLCDB
fi;

# Default for ORACLE PDB
if [ "$ORACLE_PDB" == "" ]; then
   export ORACLE_PDB=ORCLPDB1
fi;

# Check whether database already exists
if [ "`checkDBExists`" == "0" ]; then
   createDB;
else
   startDB;
fi;

echo "#########################"
echo "DATABASE IS READY TO USE!"
echo "#########################"

tail -f $ORACLE_BASE/diag/rdbms/*/*/trace/alert*.log &
childPID=$!
wait $childPID
