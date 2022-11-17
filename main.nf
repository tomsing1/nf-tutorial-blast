#! /usr/bin/env nextflow
nextflow.enable.dsl=2

def helpMessage() {
  log.info """
        Usage:
        The typical command for running the pipeline is as follows:
        nextflow run main.nf --query QUERY.fasta --dbDir "blastDatabaseDirectory" --dbName "blastPrefixName"

        Mandatory arguments:
         --query                        Query fasta file of sequences you wish to BLAST
         --dbDir                        BLAST database directory (full path required)
         --dbName                       Prefix name of the BLAST database

       Optional arguments:
        --genome                       If specified with a genome fasta file, a BLAST database will be generated for the genome
        --outdir                       Output directory to place final BLAST output
        --outfmt                       Output format ['6']
        --options                      Additional options for BLAST command [-evalue 1e-3]
        --outFileName                  Prefix name for BLAST output [input.blastout]
        --threads                      Number of CPUs to use during blast job [16]
        --chunkSize                    Number of fasta records to use when splitting the query fasta file
        --app                          BLAST program to use [blastn;blastp,tblastn,blastx]
        --help                         This usage statement.
        """
}

process runBlast {
    container = 'ncbi/blast'

    input:
    each queryFile
    path dbDir
    val dbName

    output:
    path params.outFileName

    script:
    """
    $params.app \
        -num_threads $params.threads \
        -db $dbDir/$dbName \
        -query $queryFile \
        -outfmt $params.outfmt $params.options \
        -out $params.outFileName

    """
}

process runMakeBlastDB {
    container = 'ncbi/blast'
    debug true

    input:
    tuple val(dbName), path(dbDir), path(FILE)

    output:
    val dbName, emit: dbName
    path "${dbDir}/${dbName}", emit: dbDir

    script:
    """
    makeblastdb -in $FILE -dbtype 'nucl' -out $dbDir/$dbName/$dbName
    """
}

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}

workflow {
    channel
        .fromPath(params.query)
        .splitFasta(by: 1, file:true) 
        .set { queryFile_ch }
    
    if (params.genome) {
        channel
            .fromPath(params.genome, checkIfExists: true)
            .map { file -> tuple(file.simpleName, file.parent, file) }
            .set { genomefile_ch }
        runMakeBlastDB(genomefile_ch)
        dbDir_ch = runMakeBlastDB.out.dbDir
        dbName_ch = runMakeBlastDB.out.dbName
    } else {
        channel.fromPath(params.dbDir)
            .set { dbDir_ch }
        channel.from(params.dbName)
            .set { dbName_ch }
    }

    runBlast(queryFile_ch, dbDir_ch, dbName_ch)
    runBlast.out.collectFile(
        name: 'blast_output_combined.txt', storeDir: params.outdir)
}