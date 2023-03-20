Prepare files, run in order.

1. Load all the files
vim *.txt

2. Remove unused stuff. The macro under q is already present and removes until
Experiment Duraition line 
```bash
bufdo normal@q w 
bufdo :%s/^.*msg="\(.*\) \([0-9.]\+\).*$/\1 \2/g
```

3. Format values output
`bufdo :%s/[0-9.]\+/\=system('numfmt --to=si --format %.2f', submatch(0))`

4. Transpose data to columnar layout
`bufdo :%d|:r! bash -c "datamash -t: transpose <% | column -t -s:"`
alternative with ; separator `bufdo :%d|:r! bash -c "datamash -t: transpose <% |
column -t -s: --output-separator=';'"`

5. Delete top empty line
`bufdo :g/^$/d`

8. Combine results
`fd --extension=txt | sort -V | xargs tail -n +1 | sed 's#> ./#> #g'`

6. Format columns
`%s/ of Bucket/ seconds /g`
`%s/CPU/CPU %/g`

7. Prometheus graph
`sum(node_namespace_pod_container:container_memory_working_set_bytes{pod="%s", namespace="%s"})`

