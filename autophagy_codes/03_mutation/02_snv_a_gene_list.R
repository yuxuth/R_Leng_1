library(magrittr)
tcga_path = "/home/cliu18/liucj/projects/6.autophagy/TCGA"
expr_path <- "/home/cliu18/liucj/projects/6.autophagy/02_autophagy_expr/"
expr_path_a <- file.path(expr_path, "03_a_gene_expr")
snv_path <- "/home/cliu18/liucj/projects/6.autophagy/04_snv"

# load cnv and gene list
snv <- readr::read_rds(file.path(tcga_path, "pancan_snv.rds.gz"))
gene_list <- readr::read_rds(file.path(expr_path_a, "rds_03_a_atg_lys_gene_list.rds.gz"))

filter_gene_list <- function(.x, gene_list) {
  gene_list %>%
    dplyr::select(symbol) %>%
    dplyr::left_join(.x, by = "symbol")
}

snv %>%
  dplyr::mutate(filter_snv = purrr::map(snv, filter_gene_list, gene_list = gene_list)) %>%
  dplyr::select(-snv) -> gene_list_snv

readr::write_rds(x = gene_list_snv, path = file.path(snv_path, ".rds_02_snv_a_gene_list.rds.gz"), compress = "gz")


fn_get_percent <- function(cancer_types, filter_snv){
  print(cancer_types)
  n <- length(filter_snv) - 1
  filter_snv %>%
    dplyr::mutate_if(.predicate = is.numeric, .fun = dplyr::funs(ifelse(is.na(.), 0, .))) -> .d
    .d %>% 
      tidyr::gather(key = barcode, value = count, -symbol) %>% 
      dplyr::mutate(samples = ifelse(count > 0, 1, 0)) %>% 
      dplyr::group_by(symbol) %>% 
      dplyr::summarise(sm_count = sum(count), sm_sample = sum(samples)) %>% 
      dplyr::mutate(per = sm_sample / n) -> .d_count

    tibble::tibble(cancer_types = cancer_types, n = n, mut_count = list(.d_count))
}
gene_list_snv %>% 
  head(1) %>% #.$filter_snv %>% .[[1]] -> filter_snv
  plyr::mutate(res = purrr::map2(cancer_types, filter_snv, fn_get_percent))

cl <- parallel::detectCores()
cluster <- multidplyr::create_cluster(floor(cl * 5 / 6))
gene_list_snv %>% 
  multidplyr::partition(cluster = cluster) %>%
  multidplyr::cluster_library("magrittr") %>%
  multidplyr::cluster_assign_value("fn_get_percent", fn_get_percent)  %>%
  dplyr::mutate(res = purrr::map2(cancer_types, filter_snv, fn_get_percent)) %>% 
  dplyr::collect() %>%
  dplyr::as_tibble() %>%
  dplyr::ungroup() %>%
  dplyr::select(-PARTITION_ID) %>% 
  dplyr::select(-cancer_types, -filter_snv) %>% 
  tidyr::unnest(res) -> gene_list_snv_count
on.exit(parallel::stopCluster(cluster))

library(ggplot2)
gene_list_snv_count %>% 
  tidyr::unnest(mut_count) %>% 
  tidyr::drop_na() %>%
  dplyr::mutate(x_label = paste(cancer_types, " (n=", n,")", sep = "")) %>% 
  dplyr::mutate(sm_count = ifelse(sm_count>0, sm_count, NA)) -> plot_ready

plot_ready %>% 
  dplyr::group_by(x_label) %>% 
  dplyr::summarise(s = sum(per)) %>% 
  dplyr::arrange(dplyr::desc(s)) -> cancer_rank

plot_ready %>% 
  dplyr::group_by(symbol) %>% 
  dplyr::summarise(s = sum(sm_sample)) %>% 
  dplyr::left_join(gene_list, by = "symbol") %>% 
  dplyr::mutate(color = plyr::revalue(status, replace = c('a' = "#e41a1c", "l" = "#377eb8", "i" = "#4daf4a", "p" = "#984ea3"))) %>% 
  dplyr::arrange(s) -> gene_rank

plot_ready %>% 
  dplyr::filter(!symbol %in% c("TP53", "PTEN", "CDKN2A")) %>% 
  dplyr::mutate(per = ifelse(per > 0.1, 01, per)) %>% 
  ggplot(aes(x = x_label, y = symbol, fill = per)) +
  geom_tile() +
  geom_text(aes(label = sm_count)) +
  scale_x_discrete(position = "top", limits = cancer_rank$x_label) +
  scale_y_discrete(limits = gene_rank$symbol) +
  scale_fill_gradient2(
    name = "Mutation Frequency (%)",
    limit = c(0, 0.1),
    breaks = seq(0, 0.1, 0.01),
    label = c("0", "", "", "3","", "", "",  "7", "","","10"),
    high = "red",
    na.value = "white"
  ) +
  ggthemes::theme_gdocs() +
  theme(
    axis.text.x = element_text(angle = 45, hjust = -0.05),
    axis.text.y = element_text(color = gene_rank$color)
  ) +
  guides(fill = guide_legend(title = "Mutation Frequency (%)", 
                             title.position = "left", 
                             title.theme = element_text(angle = 90, vjust = 2), 
                             reverse = T, 
                             keywidth = 0.6, 
                             keyheight = 0.8 )) -> p

ggsave(filename = "01_snv_all.pdf", plot = p, device = "pdf", path = snv_path, width = 15, height = 30)










